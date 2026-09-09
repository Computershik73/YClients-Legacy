#import "YCLoginController.h"

#import <QuartzCore/QuartzCore.h>

#import "YCAlert.h"
#import "YCApi.h"
#import "YCExpiry.h"
#import "YCIcons.h"
#import "YCProxy.h"
#import "YCProxyController.h"
#import "YCSheet.h"
#import "YCTheme.h"

#pragma mark - Общие детали оформления

/** Поле ввода со скруглённой рамкой — как в оригинале. */
static UITextField *YCField(NSString *placeholder) {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];

    field.placeholder = placeholder;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;

    // Рамка, отступы и шрифт — из темы: на iOS 6 это системный бортик,
    // на новых системах своя тонкая линия.
    [YCTheme decorateField:field];

    return field;
}

/** Серая таблетка — второстепенные кнопки «Регистрация», «Сброс пароля». */
static UIButton *YCGreyPill(NSString *title) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];

    [YCTheme decorateButton:button color:[YCTheme surface] radius:24.0];

    button.titleLabel.font = [YCTheme bodyFont];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[YCTheme text] forState:UIControlStateNormal];

    return button;
}

/** Жёлтый квадрат со знаком — вместо логотипа, который нам не принадлежит. */
static UIView *YCMark(CGFloat size) {
    UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];

    [YCTheme decoratePanel:tile color:[YCTheme text] radius:size * 0.22];

    UILabel *glyph = [[UILabel alloc] initWithFrame:tile.bounds];

    glyph.text = @"Y";
    glyph.font = [UIFont boldSystemFontOfSize:size * 0.62];
    glyph.textColor = [YCTheme accent];
    glyph.textAlignment = NSTextAlignmentCenter;
    glyph.backgroundColor = [UIColor clearColor];
    [tile addSubview:glyph];

    return tile;
}


#pragma mark - Вход

@interface YCLoginController () <UITextFieldDelegate>
@end

@implementation YCLoginController {
    UIScrollView *_scroll;
    UIView *_mark;
    UILabel *_wordmark;
    UITextField *_loginField;
    UITextField *_passwordField;
    UIButton *_eye;
    UIButton *_submit;
    UILabel *_question;
    UIButton *_register;
    UIButton *_reset;
    UILabel *_footer;
    UILabel *_expiry;
    UIButton *_proxy;
    UIActivityIndicatorView *_spinner;
    BOOL _busy;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [YCTheme background];

    // Панели навигации на экране входа нет — как в оригинале.
    [self.navigationController setNavigationBarHidden:YES animated:NO];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];

    _mark = YCMark(40);
    [_scroll addSubview:_mark];

    _wordmark = [[UILabel alloc] initWithFrame:CGRectZero];
    _wordmark.text = @"yclients";
    _wordmark.font = [UIFont boldSystemFontOfSize:30.0];
    _wordmark.textColor = [YCTheme text];
    _wordmark.backgroundColor = [UIColor clearColor];
    [_scroll addSubview:_wordmark];

    _loginField = YCField(@"Номер телефона или email");
    _loginField.keyboardType = UIKeyboardTypeEmailAddress;
    _loginField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _loginField.returnKeyType = UIReturnKeyNext;
    _loginField.delegate = self;
    [_scroll addSubview:_loginField];

    _passwordField = YCField(@"Пароль");
    _passwordField.secureTextEntry = YES;
    _passwordField.returnKeyType = UIReturnKeyGo;
    _passwordField.delegate = self;
    _passwordField.clearButtonMode = UITextFieldViewModeNever;
    [_scroll addSubview:_passwordField];

    // Глаз справа в поле пароля — показать набранное. Значок рисованный:
    // знака 👁 в шрифтах iOS 6 нет, вместо него был пустой квадрат.
    _eye = [UIButton buttonWithType:UIButtonTypeCustom];
    _eye.frame = CGRectMake(0, 0, 44, 44);
    [_eye setImage:[YCIcons eye:24 color:[YCTheme mutedText] crossed:NO]
          forState:UIControlStateNormal];
    [_eye addTarget:self action:@selector(toggleEye) forControlEvents:UIControlEventTouchUpInside];
    _passwordField.rightView = _eye;
    _passwordField.rightViewMode = UITextFieldViewModeAlways;

    _submit = [YCSheet yellowButtonWithTitle:@"Войти"];
    [_submit addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_submit];

    /**
     * Срок сборки — прямо под кнопкой входа, а не в «О программе».
     *
     * Сборка живёт неделю (см. YCExpiry), и знать об этом надо до того,
     * как она перестанет работать, а не после. Строка стоит здесь с первого
     * дня и меняет только цвет, когда срок выходит.
     */
    _expiry = [[UILabel alloc] initWithFrame:CGRectZero];
    _expiry.numberOfLines = 0;
    _expiry.font = [YCTheme captionFont];
    _expiry.textAlignment = NSTextAlignmentCenter;
    _expiry.backgroundColor = [UIColor clearColor];
    [_scroll addSubview:_expiry];

    _question = [[UILabel alloc] initWithFrame:CGRectZero];
    _question.text = @"Нет аккаунта или забыли пароль?";
    _question.font = [YCTheme bodyFont];
    _question.textColor = [YCTheme text];
    _question.textAlignment = NSTextAlignmentCenter;
    _question.backgroundColor = [UIColor clearColor];
    [_scroll addSubview:_question];

    _register = YCGreyPill(@"Регистрация");
    [_register addTarget:self action:@selector(openSite) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_register];

    _reset = YCGreyPill(@"Сброс пароля");
    [_reset addTarget:self action:@selector(openSite) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_reset];

    NSString *version = [[[NSBundle mainBundle] infoDictionary]
        objectForKey:@"CFBundleShortVersionString"] ?: @"?";

    _footer = [[UILabel alloc] initWithFrame:CGRectZero];
    _footer.text = [NSString stringWithFormat:@"Работает на YCLIENTS\nv. %@ · iOS 6+", version];
    _footer.numberOfLines = 2;
    _footer.font = [YCTheme captionFont];
    _footer.textColor = [YCTheme mutedText];
    _footer.textAlignment = NSTextAlignmentCenter;
    _footer.backgroundColor = [UIColor clearColor];
    [_scroll addSubview:_footer];

    /**
     * Прокси — маленькой строкой внизу, а не разделом.
     *
     * На экране входа он обязан быть: если вход не проходит, до настроек
     * внутри приложения не добраться. Но в оригинале его нет, и крупная
     * строка ломала бы вид; серая подпись под версией — компромисс.
     */
#ifdef YC_PROXY
    _proxy = [UIButton buttonWithType:UIButtonTypeCustom];
    _proxy.titleLabel.font = [YCTheme captionFont];
    [_proxy addTarget:self action:@selector(openProxy) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_proxy];
#endif

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:[YCTheme spinnerStyle]];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.navigationController setNavigationBarHidden:YES animated:animated];

#ifdef YC_PROXY
    [_proxy setTitle:[NSString stringWithFormat:@"Прокси для отладки: %@", [YCProxy summary]]
            forState:UIControlStateNormal];
    [_proxy setTitleColor:([YCProxy isActive] ? [YCTheme nowLine] : [YCTheme mutedText])
                 forState:UIControlStateNormal];
#endif

    [self refreshExpiry];
}

/**
 * Обновляет строку срока и запирает вход, если он вышел.
 *
 * Зовётся не только при появлении экрана, но и после каждой попытки входа:
 * время приходит с ответом сервера, и сборка, просроченная неделю назад,
 * узнаёт об этом ровно в тот миг, когда впервые дозвонилась.
 */
- (void)refreshExpiry {
    NSString *notice = [YCExpiry notice];

    _expiry.text = notice ?: @"";
    _expiry.textColor = [YCExpiry isExpired] ? [YCTheme nowLine] : [YCTheme mutedText];

    if ([YCExpiry isExpired]) {
        _submit.enabled = NO;
        _submit.alpha = 0.5;
    }

    [self.view setNeedsLayout];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    // Следующий экран — с панелью; прячем только у себя.
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;

    /**
     * Столбец содержимого ограничен по ширине.
     *
     * На iPad поля растягивались на все 768 точек — строка ввода длиной
     * в ладонь выглядит как ошибка вёрстки, а не как форма входа.
     * На телефоне ограничение не срабатывает: там ширина и так меньше.
     */
    CGFloat inner = MIN(width - 32.0, 420.0);
    CGFloat inset = (width - inner) / 2;

    // Знак и надпись — одной строкой по центру. Ширина — через sizeThatFits:,
    // а не sizeWithFont:, которого на новых системах уже нет.
    CGFloat wordWidth = [_wordmark sizeThatFits:CGSizeMake(300, 44)].width;
    CGFloat groupWidth = 40 + 10 + wordWidth;
    CGFloat groupX = (width - groupWidth) / 2;

    _mark.frame = CGRectMake(groupX, 56, 40, 40);
    _wordmark.frame = CGRectMake(groupX + 50, 56, wordWidth, 40);

    CGFloat y = 140;

    /**
     * У выпуклого оформления строки ниже.
     *
     * 56 точек — рост из плоского языка, где высоту держит пустота вокруг
     * текста. Системный бортик iOS 6 при такой высоте растягивается
     * в неправдоподобно толстую пилюлю: рядом с ним обычное поле поиска
     * системы вдвое тоньше. 46 — ближе к тамошней норме.
     */
    CGFloat row = [YCTheme isLegacy] ? 46.0 : 56.0;

    _loginField.frame = CGRectMake(inset, y, inner, row);      y += row + 12;
    _passwordField.frame = CGRectMake(inset, y, inner, row);   y += row + 32;
    _submit.frame = CGRectMake(inset, y, inner, row);          y += row + 16;

    if ([_expiry.text length] > 0) {
        CGFloat height = [_expiry sizeThatFits:CGSizeMake(inner, 200)].height;

        _expiry.frame = CGRectMake(inset, y, inner, height);   y += height + 24;
    } else {
        _expiry.frame = CGRectZero;                            y += 24;
    }

    _question.frame = CGRectMake(inset, y, inner, 24);         y += 40;

    CGFloat half = (inner - 12) / 2;

    _register.frame = CGRectMake(inset, y, half, 48);
    _reset.frame = CGRectMake(inset + half + 12, y, half, 48); y += 92;

    _footer.frame = CGRectMake(inset, y, inner, 40);           y += 48;
    /**
     * Строки о прокси в готовой сборке нет вовсе.
     *
     * Не «есть, но выключена» — самой кнопки не создаётся, потому что
     * и кода прокси в такой сборке нет (см. YC_PROXY в Makefile).
     * Место под неё тоже не отводится.
     */
#ifdef YC_PROXY
    _proxy.frame = CGRectMake(inset, y, inner, 32);            y += 48;
#endif

    _scroll.contentSize = CGSizeMake(width, MAX(y, self.view.bounds.size.height));
    _spinner.center = _submit.center;
}

#pragma mark Клавиатура

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect frame = [[[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect inView = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(inView));

    _scroll.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    _scroll.scrollIndicatorInsets = _scroll.contentInset;

    // Кнопка «Войти» должна остаться над клавиатурой.
    [_scroll scrollRectToVisible:CGRectInset(_submit.frame, 0, -24) animated:YES];
}

- (void)keyboardWillHide:(NSNotification *)note {
    _scroll.contentInset = UIEdgeInsetsZero;
    _scroll.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _loginField) {
        [_passwordField becomeFirstResponder];
        return NO;
    }

    [self submit];
    return NO;
}

#pragma mark Действия

- (void)toggleEye {
    /**
     * Смена secureTextEntry на лету — с известной ловушкой: поле теряет
     * курсор и иногда стирает текст на iOS 6. Обход — снять и вернуть
     * фокус, переписав текст руками.
     */
    NSString *text = _passwordField.text;
    BOOL wasFirst = [_passwordField isFirstResponder];

    [_passwordField resignFirstResponder];
    _passwordField.secureTextEntry = !_passwordField.secureTextEntry;
    _passwordField.text = @"";
    _passwordField.text = text;

    [_eye setImage:[YCIcons eye:24 color:[YCTheme mutedText]
                        crossed:!_passwordField.secureTextEntry]
          forState:UIControlStateNormal];

    if (wasFirst) {
        [_passwordField becomeFirstResponder];
    }
}

- (void)openSite {
    // Регистрация и сброс пароля — на сайте: своих экранов для них
    // у API нет, а подделывать их формой было бы хуже, чем отправить туда.
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://yclients.com/"]];
}

#ifdef YC_PROXY
- (void)openProxy {
    [self.view endEditing:YES];
    [self.navigationController pushViewController:[[YCProxyController alloc] init] animated:YES];
}
#endif

- (void)setBusy:(BOOL)busy {
    _busy = busy;

    if (busy) {
        [_spinner startAnimating];
    } else {
        [_spinner stopAnimating];
    }

    _submit.enabled = !busy && ![YCExpiry isExpired];
    _submit.alpha = _submit.enabled ? 1.0 : 0.5;
    _scroll.userInteractionEnabled = !busy;
}

- (void)submit {
    if (_busy) {
        return;
    }

    if ([YCExpiry isExpired]) {
        YCAlertMessage(self, @"Срок сборки истёк", [YCExpiry notice]);
        return;
    }

    NSString *login = [_loginField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *password = _passwordField.text ?: @"";

    if ([login length] == 0 || [password length] == 0) {
        YCAlertMessage(self, @"Заполните оба поля",
                       @"Нужны логин и пароль от учётной записи YClients.");
        return;
    }

    [self.view endEditing:YES];
    [self setBusy:YES];

    [[YCApi shared] loginWithLogin:login password:password
                        completion:^(BOOL ok, NSString *error) {
        [self setBusy:NO];

        /**
         * Срок проверяется после запроса, а не до него.
         *
         * Настоящее время приходит заголовком Date в ответе сервера —
         * в том числе в ответе с отказом. То есть первая же попытка входа
         * и сообщает сборке, жива она ещё или нет.
         */
        [self refreshExpiry];

        if ([YCExpiry isExpired]) {
            YCAlertMessage(self, @"Срок сборки истёк", [YCExpiry notice]);
            return;
        }

        if (!ok) {
            YCAlertMessage(self, @"Не удалось войти", error);
            return;
        }

        // Пароль стирается сразу: дальше он не нужен ни для чего.
        self->_passwordField.text = @"";

        YCCompaniesController *companies = [[YCCompaniesController alloc] init];

        companies.delegate = self.delegate;

        [self.navigationController pushViewController:companies animated:YES];
    }];
}

@end


#pragma mark - Филиалы

@interface YCCompaniesController () <UISearchBarDelegate>
@end

@implementation YCCompaniesController {
    NSArray *_companies;
    NSArray *_shown;
    UISearchBar *_search;
    UIActivityIndicatorView *_spinner;
}

- (id)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Филиалы";
    [YCTheme decorateTable:self.tableView color:[YCTheme background]];
    self.tableView.rowHeight = 76.0;
    self.tableView.separatorColor = [YCTheme gridLine];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    // Слева — выход из учётной записи, как значок «дверь» в оригинале.
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Выйти"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(logout)];

    self.navigationItem.hidesBackButton = YES;

    _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 56)];
    _search.placeholder = @"Поиск";
    _search.delegate = self;
    _search.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    if ([_search respondsToSelector:@selector(setSearchBarStyle:)]) {
        [_search setSearchBarStyle:UISearchBarStyleMinimal];
    }

    [YCTheme decorateSearchBar:_search];

    self.tableView.tableHeaderView = _search;

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:[YCTheme spinnerStyle]];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    [self load];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds), 160);
}

- (void)load {
    [_spinner startAnimating];

    [[YCApi shared] loadCompaniesWithCompletion:^(NSArray *companies, NSString *error) {
        [self->_spinner stopAnimating];

        if (error != nil) {
            YCAlertMessage(self, @"Филиалы не получены", error);
            return;
        }

        self->_companies = companies;
        self->_shown = companies;

        /**
         * Один филиал выбирается сам — но только при входе.
         *
         * Когда о смене филиала попросили явно, тот же самовыбор выглядит
         * поломкой: список мигает и возвращает в журнал. Показанный список
         * из одной строки хотя бы объясняет, почему менять не на что.
         */
        if ([companies count] == 1 && !self.explicitChoice) {
            [[YCApi shared] selectCompany:[companies objectAtIndex:0]];
            [self.delegate loginControllerDidFinish:self];
            return;
        }

        [self.tableView reloadData];
    }];
}

- (void)logout {
    YCAlertConfirm(self, @"Выйти из учётной записи?",
                   @"Токен будет удалён с устройства. Записи это не затронет.",
                   @"Выйти", YES, ^{
        [[YCApi shared] logout];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:YCDidLogOutNotification object:nil];
    });
}

#pragma mark Поиск

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    if ([text length] == 0) {
        _shown = _companies;
    } else {
        NSMutableArray *matching = [NSMutableArray array];

        for (YCCompany *company in _companies) {
            if ([company.title rangeOfString:text
                                     options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [company.city rangeOfString:text
                                    options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matching addObject:company];
            }
        }

        _shown = matching;
    }

    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark Список

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_shown count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    YCCompany *company = [_shown objectAtIndex:path.row];

    [YCTheme decorateCell:cell];
    cell.textLabel.text = company.title;
    cell.textLabel.font = [YCTheme titleFont];
    cell.textLabel.textColor = [YCTheme text];

    cell.detailTextLabel.text = company.city;
    cell.detailTextLabel.font = [YCTheme bodyFont];
    cell.detailTextLabel.textColor = [YCTheme text];

    // Жёлтый круг со знаком — как логотип филиала в оригинале.
    UIView *logo = YCMark(48);
    [YCTheme decoratePanel:logo color:[YCTheme accent] radius:24.0];
    /**
     * Подпись ищется по классу, а не по нулевому индексу.
     *
     * Индекс был верен ровно до того дня, когда выпуклое оформление стало
     * подкладывать под вид подложку — она встаёт самой нижней, то есть
     * как раз нулевой, и вместо надписи сюда попадала она. Просьба
     * покрасить у неё текст роняла приложение на списке филиалов.
     */
    for (UIView *sub in logo.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            [(UILabel *)sub setTextColor:[YCTheme text]];
        }
    }

    // Круг в imageView не положить видом, поэтому — снимком.
    UIGraphicsBeginImageContextWithOptions(logo.bounds.size, NO, 0);
    [logo.layer renderInContext:UIGraphicsGetCurrentContext()];
    cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    [[YCApi shared] selectCompany:[_shown objectAtIndex:path.row]];
    [self.delegate loginControllerDidFinish:self];
}

@end
