#import "YCDrawerController.h"

#import "YCApi.h"
#import "YCIcons.h"
#import "YCTheme.h"

/** Ширина шторки: не больше трёх четвертей экрана. */
static const CGFloat YCDrawerWidth = 264.0;

@interface YCDrawerController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation YCDrawerController {
    UIView *_contentHolder;
    UIView *_dimmer;
    UITableView *_menu;
    UIView *_header;
    UILabel *_companyLabel;
    BOOL _open;
}

- (id)initWithContentController:(UIViewController *)content {
    self = [super init];

    if (self != nil) {
        _contentController = content;
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [YCTheme darkPanel];

    /**
     * Шторка лежит **под** содержимым и не двигается.
     *
     * Двигается содержимое — вправо, открывая её. Так проще: панель
     * рисуется один раз на своём месте, и её не приходится держать
     * за краем экрана, где на неё нельзя нажать, но можно случайно
     * оказаться при повороте.
     */
    [self buildMenu];

    _contentHolder = [[UIView alloc] initWithFrame:self.view.bounds];
    _contentHolder.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                      UIViewAutoresizingFlexibleHeight;
    _contentHolder.backgroundColor = [YCTheme background];
    [self.view addSubview:_contentHolder];

    _dimmer = [[UIView alloc] initWithFrame:_contentHolder.bounds];
    _dimmer.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                               UIViewAutoresizingFlexibleHeight;
    _dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];
    _dimmer.hidden = YES;

    [_dimmer addGestureRecognizer:
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeDrawer)]];

    [self attachContent];
}

- (void)buildMenu {
    _header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, YCDrawerWidth, 96)];
    _header.backgroundColor = [UIColor clearColor];

    UIView *mark = [[UIView alloc] initWithFrame:CGRectMake(16, 32, 44, 44)];

    [YCTheme decoratePanel:mark color:[YCTheme accent] radius:10.0];

    UILabel *glyph = [[UILabel alloc] initWithFrame:mark.bounds];

    glyph.text = @"Y";
    glyph.font = [UIFont boldSystemFontOfSize:24.0];
    glyph.textColor = [YCTheme text];
    glyph.textAlignment = NSTextAlignmentCenter;
    glyph.backgroundColor = [UIColor clearColor];
    [mark addSubview:glyph];
    [_header addSubview:mark];

    _companyLabel = [[UILabel alloc] initWithFrame:
        CGRectMake(72, 32, YCDrawerWidth - 88, 44)];

    _companyLabel.font = [YCTheme titleFont];
    _companyLabel.textColor = [UIColor whiteColor];
    _companyLabel.backgroundColor = [UIColor clearColor];
    _companyLabel.numberOfLines = 2;
    _companyLabel.adjustsFontSizeToFitWidth = YES;
    _companyLabel.minimumScaleFactor = 0.7;
    [_header addSubview:_companyLabel];

    _menu = [[UITableView alloc] initWithFrame:
        CGRectMake(0, 0, YCDrawerWidth, self.view.bounds.size.height)
                                          style:UITableViewStylePlain];

    _menu.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    _menu.backgroundColor = [YCTheme darkPanel];
    _menu.separatorStyle = UITableViewCellSeparatorStyleNone;
    _menu.dataSource = self;
    _menu.delegate = self;
    _menu.rowHeight = 48.0;
    _menu.tableHeaderView = _header;

    // На iOS 6 сгруппированную подложку рисует отдельный вид; здесь список
    // обычный, но фон всё равно задаётся явно — см. YCTheme.
    if ([YCTheme isLegacy]) {
        _menu.backgroundView = nil;
    }

    [self.view addSubview:_menu];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    _companyLabel.text = [[YCApi shared] companyTitle] ?: @"YClients";

    [_menu reloadData];
}

#pragma mark Содержимое

- (void)attachContent {
    if (_contentController == nil) {
        return;
    }

    [self addChildViewController:_contentController];

    _contentController.view.frame = _contentHolder.bounds;
    _contentController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                               UIViewAutoresizingFlexibleHeight;

    [_contentHolder addSubview:_contentController.view];
    [_contentHolder addSubview:_dimmer];

    if ([_contentController respondsToSelector:@selector(didMoveToParentViewController:)]) {
        [_contentController didMoveToParentViewController:self];
    }
}

- (void)setContentController:(UIViewController *)contentController {
    if (contentController == _contentController) {
        [self closeDrawer];
        return;
    }

    UIViewController *old = _contentController;

    if (old != nil) {
        if ([old respondsToSelector:@selector(willMoveToParentViewController:)]) {
            [old willMoveToParentViewController:nil];
        }

        [old.view removeFromSuperview];
        [old removeFromParentViewController];
    }

    _contentController = contentController;

    [self attachContent];
    [self closeDrawer];
}

#pragma mark Открытие

- (BOOL)isOpen {
    return _open;
}

- (void)toggleDrawer {
    if (_open) {
        [self closeDrawer];
    } else {
        [self openDrawer];
    }
}

- (void)openDrawer {
    if (_open) {
        return;
    }

    _open = YES;

    // Клавиатура под съехавшим содержимым выглядит забытой.
    [self.view endEditing:YES];

    _dimmer.hidden = NO;

    [UIView animateWithDuration:0.22
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        CGRect frame = self.view.bounds;

        frame.origin.x = YCDrawerWidth;
        self->_contentHolder.frame = frame;
        self->_dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    }
                     completion:nil];
}

- (void)closeDrawer {
    if (!_open) {
        return;
    }

    _open = NO;

    [UIView animateWithDuration:0.20
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_contentHolder.frame = self.view.bounds;
        self->_dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];
    }
                     completion:^(BOOL finished) {
        self->_dimmer.hidden = YES;
    }];
}

#pragma mark Пункты

/** Заголовок и значок по номеру пункта. */
- (NSString *)titleForItem:(YCDrawerItem)item {
    switch (item) {
        case YCDrawerItemJournal:    return @"Журнал";
        case YCDrawerItemMonth:      return @"Календарь на месяц";
        case YCDrawerItemClients:    return @"Клиенты";
        case YCDrawerItemAppearance: return @"Оформление";
        case YCDrawerItemAbout:      return @"О программе";
        case YCDrawerItemCompany:    return @"Сменить филиал";
        case YCDrawerItemLogout:     return @"Выйти";
        default:                     return @"";
    }
}

- (UIImage *)iconForItem:(YCDrawerItem)item color:(UIColor *)color {
    switch (item) {
        case YCDrawerItemJournal:    return [YCIcons calendar:24 color:color];
        case YCDrawerItemMonth:      return [YCIcons calendar:24 color:color];
        case YCDrawerItemClients:    return [YCIcons people:24 color:color];
        case YCDrawerItemAppearance: return [YCIcons clock:24 color:color];
        case YCDrawerItemAbout:      return [YCIcons comment:24 color:color];
        case YCDrawerItemCompany:    return [YCIcons menu:24 color:color];
        case YCDrawerItemLogout:     return [YCIcons close:24 color:color];
        default:                     return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return YCDrawerItemCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                               reuseIdentifier:nil];

    YCDrawerItem item = (YCDrawerItem)path.row;

    /**
     * Шторка всегда тёмная, независимо от темы.
     *
     * Она лежит под содержимым и видна только вместе с затемнением —
     * светлая панель за тёмной вуалью выглядит грязно-серой. К тому же
     * так она отделена от содержимого без единой линии.
     */
    UIColor *ink = (item == YCDrawerItemLogout) ? [YCTheme nowLine] : [UIColor whiteColor];

    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.text = [self titleForItem:item];
    cell.textLabel.font = [YCTheme rowFont];
    cell.textLabel.textColor = ink;
    cell.imageView.image = [self iconForItem:item color:ink];

    UIView *selected = [[UIView alloc] initWithFrame:CGRectZero];

    selected.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    cell.selectedBackgroundView = selected;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    YCDrawerItem item = (YCDrawerItem)path.row;

    [self closeDrawer];

    [self.drawerDelegate drawer:self didChooseItem:item];
}

#pragma mark Поворот

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // При повороте открытая шторка должна остаться открытой ровно
    // на ту же ширину, а закрытая — не показать края.
    CGRect frame = self.view.bounds;

    frame.origin.x = _open ? YCDrawerWidth : 0;
    _contentHolder.frame = frame;
}

@end
