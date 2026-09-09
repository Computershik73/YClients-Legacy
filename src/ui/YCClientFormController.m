#import "YCClientFormController.h"

#import <QuartzCore/QuartzCore.h>

#import "YCApi.h"
#import "YCIcons.h"
#import "YCModel.h"
#import "YCSheet.h"
#import "YCTheme.h"

@interface YCClientFormController () <UITextFieldDelegate,
                                     UITableViewDataSource, UITableViewDelegate>
@end

@implementation YCClientFormController {
    UITextField *_phone;
    UITextField *_name;
    UITextField *_email;
    UIButton *_button;
    UIScrollView *_scroll;
    CGFloat _keyboardOverlap;
    void (^_onChoose)(NSString *, NSString *, NSString *);

    /**
     * Найденные в базе филиала — по тому, что набирают в телефоне или имени.
     *
     * Экран назывался «Клиент», но завести умел только нового: три пустых
     * поля и ничего больше. Постоянный клиент, который звонит третий год,
     * заводился заново при каждой записи — с той разницей в написании
     * имени, какая случилась в этот раз, и с новой карточкой в базе.
     */
    NSArray *_matches;
    UITableView *_results;
    NSInteger _searchGeneration;
}

- (id)initWithName:(NSString *)name
             phone:(NSString *)phone
             email:(NSString *)email
          onChoose:(void (^)(NSString *, NSString *, NSString *))onChoose {
    self = [super init];

    if (self != nil) {
        _onChoose = [onChoose copy];

        _phone = [self fieldWithPlaceholder:@"Телефон" text:phone];
        _phone.keyboardType = UIKeyboardTypePhonePad;

        _name = [self fieldWithPlaceholder:@"Имя" text:name];
        _name.autocapitalizationType = UITextAutocapitalizationTypeWords;

        _email = [self fieldWithPlaceholder:@"Email" text:email];
        _email.keyboardType = UIKeyboardTypeEmailAddress;
        _email.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }

    return self;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];

    field.placeholder = placeholder;
    field.text = text ?: @"";
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyNext;
    field.delegate = self;

    [YCTheme decorateField:field];

    [field addTarget:self action:@selector(textChanged)
    forControlEvents:UIControlEventEditingChanged];

    return field;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Клиент";
    self.view.backgroundColor = [YCTheme background];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    /**
     * Поля живут в прокручиваемом виде.
     *
     * Раньше они стояли прямо на экране, а кнопка поднималась над
     * клавиатурой — и на iPhone 4 садилась ровно поверх полей: экран
     * высотой 416 точек минус клавиатура в 216 оставляет 200, а три поля
     * с отступами занимают 232. Прокрутки не было, и добраться до почты
     * было нельзя вовсе.
     */
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                               UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];

    [_scroll addSubview:_phone];
    [_scroll addSubview:_name];
    [_scroll addSubview:_email];

    _results = [[UITableView alloc] initWithFrame:CGRectZero
                                            style:UITableViewStylePlain];

    _results.dataSource = self;
    _results.delegate = self;
    _results.rowHeight = 52.0;
    _results.hidden = YES;

    [YCTheme decorateTable:_results color:[YCTheme background]];

    [self.view addSubview:_results];

    _button = [YCSheet yellowButtonWithTitle:@""];
    [_button addTarget:self action:@selector(done) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_button];

    [self textChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [_phone becomeFirstResponder];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;

    // Столбец ограничен по ширине — на iPad поле во весь экран выглядит
    // ошибкой вёрстки, как и на экране входа.
    CGFloat inner = MIN(width - 32, 420);
    CGFloat inset = (width - inner) / 2;
    CGFloat row = [YCTheme isLegacy] ? 46.0 : 56.0;
    CGFloat step = row + 16.0;

    CGFloat fields = 16 + step * 3;

    /**
     * Найденные занимают низ экрана, поля остаются наверху.
     *
     * Список показывается только когда есть кого показывать: пустая
     * таблица под полями — это обещание, что кто-то найдётся, а его
     * никто не давал.
     */
    CGFloat bottom = self.view.bounds.size.height - _keyboardOverlap - row - 24;
    CGFloat resultsTop = MIN(fields, MAX(bottom - 180, row));

    if (_results.hidden) {
        _scroll.frame = self.view.bounds;
        _results.frame = CGRectZero;
    } else {
        _scroll.frame = CGRectMake(0, 0, width, resultsTop);
        _results.frame = CGRectMake(0, resultsTop, width, MAX(bottom - resultsTop, 0));
    }

    _phone.frame = CGRectMake(inset, 16, inner, row);
    _name.frame = CGRectMake(inset, 16 + step, inner, row);
    _email.frame = CGRectMake(inset, 16 + step * 2, inner, row);

    _scroll.contentSize = CGSizeMake(width, fields);

    _button.frame = CGRectMake(inset, self.view.bounds.size.height - row - 16, inner, row);

    [self insetScrollBy:(_results.hidden ? _keyboardOverlap : 0)];
}

/**
 * Оставляет под клавиатурой и кнопкой место, чтобы поля до них доходили.
 *
 * Кнопка не часть прокрутки — она прибита к низу, — поэтому её высоту
 * приходится добавлять к отступу вручную: иначе последнее поле окажется
 * ровно под ней и нажать по нему будет нельзя.
 */
- (void)insetScrollBy:(CGFloat)overlap {
    CGFloat row = [YCTheme isLegacy] ? 46.0 : 56.0;
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap + row + 32, 0);

    _scroll.contentInset = insets;
    _scroll.scrollIndicatorInsets = insets;
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect frame = [[[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect inView = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(inView));

    _keyboardOverlap = overlap;

    CGFloat width = self.view.bounds.size.width;
    CGFloat inner = MIN(width - 32, 420);
    CGFloat inset = (width - inner) / 2;
    CGFloat row = [YCTheme isLegacy] ? 46.0 : 56.0;

    // Кнопка поднимается над клавиатурой, а поля отъезжают из-под неё
    // отступом прокрутки.
    _button.frame = CGRectMake(inset, self.view.bounds.size.height - overlap - row - 16,
                               inner, row);

    [self.view setNeedsLayout];
}

- (void)keyboardWillHide:(NSNotification *)note {
    _keyboardOverlap = 0;

    [self.view setNeedsLayout];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _phone) {
        [_name becomeFirstResponder];
    } else if (textField == _name) {
        [_email becomeFirstResponder];
    } else {
        [self done];
    }

    return NO;
}

- (BOOL)isEmpty {
    return [[_phone.text stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]] length] == 0 &&
           [[_name.text stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]] length] == 0;
}

- (void)textChanged {
    [_button setTitle:([self isEmpty] ? @"Продолжить без клиента" : @"Сохранить")
             forState:UIControlStateNormal];

    [self scheduleSearch];
}

#pragma mark Поиск по базе

/**
 * Ищем с задержкой в треть секунды после последнего нажатия.
 *
 * Без задержки запрос уходил бы на каждую букву, и на телефоне пришло бы
 * семь ответов на «Иванов» — причём в произвольном порядке, так что
 * последним на экране мог оказаться ответ на «Ив».
 */
- (void)scheduleSearch {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(runSearch)
                                               object:nil];

    [self performSelector:@selector(runSearch) withObject:nil afterDelay:0.35];
}

/** Что искать: то, что набирают, — телефон или имя. */
- (NSString *)query {
    NSCharacterSet *blank = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *phone = [_phone.text stringByTrimmingCharactersInSet:blank];
    NSString *name = [_name.text stringByTrimmingCharactersInSet:blank];

    /**
     * Телефон вперёд имени: по нему находят однозначно.
     *
     * Три цифры — уже осмысленный запрос по телефону, а вот по имени
     * три буквы дадут пол-базы, поэтому для имени порог выше.
     */
    if ([phone length] >= 3) {
        return phone;
    }

    return [name length] >= 3 ? name : @"";
}

- (void)runSearch {
    NSString *query = [self query];

    if ([query length] == 0) {
        _matches = nil;

        [self showResults];
        return;
    }

    NSInteger generation = ++_searchGeneration;

    [[YCApi shared] searchClients:query partial:nil
                       completion:^(NSArray *clients, NSString *error) {
        // Ответ на прежний запрос: пришёл позже, а показывать надо
        // то, что набрано сейчас.
        if (generation != self->_searchGeneration) {
            return;
        }

        self->_matches = clients;

        [self showResults];
    }];
}

- (void)showResults {
    _results.hidden = ([_matches count] == 0);

    [_results reloadData];
    [self.view setNeedsLayout];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_matches count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Уже есть в базе";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    YCClient *client = [_matches objectAtIndex:path.row];
    NSString *shown = [client.fullName length] > 0 ? client.fullName : client.name;

    [YCTheme decorateCell:cell];

    cell.textLabel.text = [shown length] > 0 ? shown : @"Без имени";
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.text = client.phone;
    cell.detailTextLabel.font = [YCTheme captionFont];
    cell.detailTextLabel.textColor = [YCTheme mutedText];
    cell.imageView.image = [YCIcons avatar:32];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    YCClient *client = [_matches objectAtIndex:path.row];
    NSString *shown = [client.fullName length] > 0 ? client.fullName : client.name;

    /**
     * Выбор заполняет поля и сразу возвращает.
     *
     * Не «подставил и жди подтверждения»: выбрать человека из базы —
     * это и есть ответ на вопрос экрана, и лишнее нажатие «Сохранить»
     * после него ничего не добавляет.
     *
     * Запись привяжется к его карточке по телефону — сервер сводит
     * клиентов именно по нему, — так что вторая карточка не заведётся.
     */
    _name.text = shown;
    _phone.text = client.phone ?: @"";
    _email.text = client.email ?: @"";

    [self done];
}

- (void)done {
    [self.view endEditing:YES];

    NSCharacterSet *blank = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    if (_onChoose != NULL) {
        _onChoose([_name.text stringByTrimmingCharactersInSet:blank],
                  [_phone.text stringByTrimmingCharactersInSet:blank],
                  [_email.text stringByTrimmingCharactersInSet:blank]);
    }

    [self.navigationController popViewControllerAnimated:YES];
}

@end
