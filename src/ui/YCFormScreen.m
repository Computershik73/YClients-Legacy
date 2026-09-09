#import "YCFormScreen.h"

#import "YCSheet.h"
#import "YCTheme.h"

/** Поля вокруг кнопки. */
static const CGFloat YCButtonInset = 16.0;
static const CGFloat YCButtonHeight = 52.0;

@implementation YCFormScreen {
    UITableViewStyle _style;
    NSString *_buttonTitle;
    CGFloat _keyboardOverlap;
}

- (id)initWithStyle:(UITableViewStyle)style buttonTitle:(NSString *)buttonTitle {
    self = [super init];

    if (self != nil) {
        _style = style;
        _buttonTitle = [buttonTitle copy];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [YCTheme background];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:_style];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [YCTheme decorateTable:_tableView color:[YCTheme background]];
    _tableView.separatorColor = [YCTheme gridLine];
    _tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    if (_buttonTitle != nil) {
        _button = [YCSheet yellowButtonWithTitle:_buttonTitle];

        [_button addTarget:self action:@selector(buttonTapped)
          forControlEvents:UIControlEventTouchUpInside];

        [self.view addSubview:_button];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yc_keyboardWillChange:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yc_keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setAccessoryView:(UIView *)accessoryView {
    [_accessoryView removeFromSuperview];

    _accessoryView = accessoryView;

    if (accessoryView != nil) {
        [self.view addSubview:accessoryView];
    }

    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;

    /**
     * Кнопка стоит над клавиатурой, а без неё — у нижнего края.
     *
     * Таблица при этом занимает весь вид, а место под кнопку ей отдаётся
     * отступом снизу: так последняя строка доступна, а фон под кнопкой
     * остаётся таблицей, без белой полосы поперёк экрана.
     */
    CGFloat bottom = bounds.size.height - _keyboardOverlap;
    CGFloat reserved = 0;

    if (_button != nil) {
        _button.frame = CGRectMake(YCButtonInset,
                                   bottom - YCButtonInset - YCButtonHeight,
                                   width - YCButtonInset * 2, YCButtonHeight);

        reserved = YCButtonHeight + YCButtonInset * 2;
    }

    if (self.accessoryView != nil) {
        CGSize size = self.accessoryView.frame.size;

        self.accessoryView.frame = CGRectMake((width - size.width) / 2,
                                              bottom - reserved - size.height - 4,
                                              size.width, size.height);

        reserved += size.height + 8;
    }

    _tableView.frame = bounds;

    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, _keyboardOverlap + reserved, 0);

    _tableView.contentInset = insets;
    _tableView.scrollIndicatorInsets = insets;
}

#pragma mark Клавиатура

- (void)yc_keyboardWillChange:(NSNotification *)note {
    CGRect frame = [[[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];

    /**
     * Перевод кадра клавиатуры делается через окно, а не через self.view.
     *
     * У прокручиваемого вида bounds.origin равен смещению прокрутки,
     * и пересчёт «в его координаты» смешал бы положение клавиатуры
     * с тем, насколько список прокручен.
     */
    UIWindow *window = self.view.window;

    if (window == nil) {
        return;
    }

    CGRect inWindow = [window convertRect:frame fromWindow:nil];
    CGRect inView = [self.view convertRect:inWindow fromView:window];

    _keyboardOverlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(inView));

    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)yc_keyboardWillHide:(NSNotification *)note {
    _keyboardOverlap = 0;

    [self.view setNeedsLayout];
}

- (void)buttonTapped {
}

#pragma mark Пустая таблица по умолчанию

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    return [[UITableViewCell alloc] init];
}

@end
