#import "YCClientFormController.h"

#import <QuartzCore/QuartzCore.h>

#import "YCSheet.h"
#import "YCTheme.h"

@interface YCClientFormController () <UITextFieldDelegate>
@end

@implementation YCClientFormController {
    UITextField *_phone;
    UITextField *_name;
    UITextField *_email;
    UIButton *_button;
    UIScrollView *_scroll;
    CGFloat _keyboardOverlap;
    void (^_onChoose)(NSString *, NSString *, NSString *);
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

    _scroll.frame = self.view.bounds;

    _phone.frame = CGRectMake(inset, 16, inner, row);
    _name.frame = CGRectMake(inset, 16 + step, inner, row);
    _email.frame = CGRectMake(inset, 16 + step * 2, inner, row);

    _scroll.contentSize = CGSizeMake(width, 16 + step * 3);

    _button.frame = CGRectMake(inset, self.view.bounds.size.height - row - 16, inner, row);

    [self insetScrollBy:_keyboardOverlap];
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

    [self insetScrollBy:overlap];
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
