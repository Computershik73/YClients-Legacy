#import "YCClientsController.h"

#import <QuartzCore/QuartzCore.h>

#import "YCAboutController.h"
#import "YCAlert.h"
#import "YCAppearanceController.h"
#import "YCApi.h"
#import "YCClientRecordsController.h"
#import "YCIcons.h"
#import "YCProxy.h"
#import "YCProxyController.h"
#import "YCTheme.h"

#pragma mark - Клиенты

@interface YCClientsController () <UISearchBarDelegate>
@end

@implementation YCClientsController {
    UISearchBar *_search;
    NSArray *_clients;
    NSString *_query;
    NSInteger _generation;
    UIActivityIndicatorView *_spinner;
    UILabel *_empty;
}

- (id)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Клиенты";
    self.tableView.rowHeight = [YCTheme rowHeight] + 4;
    self.tableView.separatorColor = [YCTheme gridLine];
    [YCTheme decorateTable:self.tableView color:[YCTheme background]];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 56)];
    _search.placeholder = @"Поиск по имени или телефону";
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

    _empty = [[UILabel alloc] initWithFrame:CGRectZero];
    _empty.text = @"Никого не нашлось";
    _empty.font = [YCTheme bodyFont];
    _empty.textColor = [YCTheme mutedText];
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.backgroundColor = [UIColor clearColor];
    _empty.hidden = YES;
    [self.view addSubview:_empty];

    _query = @"";
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds), 140);
    _empty.frame = CGRectMake(16, 120, self.view.bounds.size.width - 32, 32);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (_clients == nil) {
        [self reload];
    }
}

/**
 * Поиск с задержкой: запрос уходит, когда набор остановился на полсекунды.
 *
 * Иначе на каждую букву шёл бы запрос, и на медленной сети ответы
 * приходили бы вразнобой. Номер поколения отбрасывает опоздавшие.
 */
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    _query = text ?: @"";

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.5];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self reload];
}

/**
 * Прикосновение к списку убирает клавиатуру.
 *
 * Искать по кнопке «Найти» никто не станет: набрали три буквы, список
 * сам обновился — и тут же оказался наполовину закрыт клавиатурой,
 * а убрать её было нечем. Теперь достаточно потянуть список.
 *
 * keyboardDismissMode сделал бы то же самое одной строкой, но он
 * с iOS 7, а нижняя граница у нас шестая.
 */
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if ([_search isFirstResponder]) {
        [_search resignFirstResponder];
    }
}

- (void)reload {
    NSInteger generation = ++_generation;

    [_spinner startAnimating];
    _empty.hidden = YES;

    [[YCApi shared] searchClients:_query partial:^(NSArray *clients) {
        // Порция пришла — показываем сразу, не дожидаясь остальных.
        if (generation != self->_generation) {
            return;
        }

        self->_clients = clients;
        self->_empty.hidden = YES;

        [self.tableView reloadData];
    } completion:^(NSArray *clients, NSString *error) {
        if (generation != self->_generation) {
            return;
        }

        [self->_spinner stopAnimating];

        if (error != nil) {
            YCAlertMessage(self, @"Клиенты не получены", error);
            return;
        }

        self->_clients = clients;
        self->_empty.hidden = ([clients count] > 0);

        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_clients count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    YCClient *client = [_clients objectAtIndex:path.row];

    [YCTheme decorateCell:cell];
    cell.imageView.image = [YCIcons avatar:[YCTheme avatarSize]];
    NSString *shown = [client.fullName length] > 0 ? client.fullName : client.name;

    cell.textLabel.text = [shown length] > 0 ? shown : @"Без имени";
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.text = client.phone;
    cell.detailTextLabel.textColor = [YCTheme mutedText];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    YCClient *client = [_clients objectAtIndex:path.row];

    /**
     * Нажатие ведёт к записям клиента, а не к его данным.
     *
     * Раньше здесь показывалось окошко с телефоном и почтой — то, что
     * и так видно в строке списка. Спрашивают же не про почту: звонит
     * человек, и надо вспомнить, что ему делали в прошлый раз.
     */
    NSString *shown = [client.fullName length] > 0 ? client.fullName : client.name;

    YCClientRecordsController *records =
        [[YCClientRecordsController alloc] initWithClientId:client.clientId
                                                       name:shown
                                                      phone:client.phone];

    [self.navigationController pushViewController:records animated:YES];
}

@end


#pragma mark - Ещё

typedef enum {
    YCMoreProfile = 0,
    YCMoreCompany,
    YCMoreStaff,
    YCMoreServices,
    YCMoreAppearance,

    /**
     * Строки прокси нет в готовой сборке — вместе с самим прокси.
     *
     * Выброшена прямо из перечисления: следующие значения сдвигаются сами,
     * YCMoreCount уменьшается, и ни таблицу, ни обработчик нажатий править
     * не приходится. Строки в двоичном файле при этом не остаётся вовсе.
     */
#ifdef YC_PROXY
    YCMoreProxy,
#endif

    YCMoreAbout,
    YCMoreLogout,
    YCMoreCount
} YCMoreRow;

@implementation YCMoreController

- (id)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Ещё";
    self.tableView.rowHeight = [YCTheme rowHeight];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [YCTheme decorateTable:self.tableView color:[YCTheme background]];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return YCMoreCount;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    return (path.row == YCMoreProfile || path.row == YCMoreCompany) ? 68.0 : [YCTheme rowHeight];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    cell.textLabel.font = [YCTheme rowFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.font = [YCTheme captionFont];
    cell.detailTextLabel.textColor = [YCTheme mutedText];
    cell.accessoryView = [[UIImageView alloc]
        initWithImage:[YCIcons chevronRight:20 color:[YCTheme mutedText]]];

    UIColor *ink = [YCTheme text];

    switch (path.row) {
        case YCMoreProfile:
            cell.imageView.image = [YCIcons avatar:[YCTheme avatarSize]];
            cell.textLabel.text = [[YCApi shared] userName];
            cell.accessoryView = nil;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;

        case YCMoreCompany: {
            // Жёлтый круг со знаком — логотип филиала.
            UIView *logo = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 52, 52)];
            [YCTheme decoratePanel:logo color:[YCTheme accent] radius:26.0];

            UILabel *glyph = [[UILabel alloc] initWithFrame:logo.bounds];
            glyph.text = @"Y";
            glyph.font = [UIFont boldSystemFontOfSize:30.0];
            glyph.textColor = [YCTheme text];
            glyph.textAlignment = NSTextAlignmentCenter;
            glyph.backgroundColor = [UIColor clearColor];
            [logo addSubview:glyph];

            UIGraphicsBeginImageContextWithOptions(logo.bounds.size, NO, 0);
            [logo.layer renderInContext:UIGraphicsGetCurrentContext()];
            cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            cell.textLabel.text = [[YCApi shared] companyTitle];
            cell.detailTextLabel.text = @"Филиал";
            break;
        }

        case YCMoreStaff:
            cell.imageView.image = [YCIcons person:24 color:ink];
            cell.textLabel.text = @"Сотрудники";
            break;

        case YCMoreServices:
            cell.imageView.image = [YCIcons menu:24 color:ink];
            cell.textLabel.text = @"Услуги";
            break;

        case YCMoreAppearance:
            cell.imageView.image = [YCIcons clock:24 color:ink];
            cell.textLabel.text = @"Оформление";
            cell.detailTextLabel.text = [@[ @"как в системе", @"светлая", @"тёмная" ]
                objectAtIndex:[YCTheme appearance]];
            break;

#ifdef YC_PROXY
        case YCMoreProxy:
            cell.imageView.image = [YCIcons search:24 color:ink];
            cell.textLabel.text = @"Прокси для отладки";
            cell.detailTextLabel.text = [YCProxy summary];
            cell.detailTextLabel.textColor = [YCProxy isActive] ? [YCTheme nowLine]
                                                                : [YCTheme mutedText];
            break;
#endif

        case YCMoreAbout:
            cell.imageView.image = [YCIcons comment:24 color:ink];
            cell.textLabel.text = @"О программе";
            break;

        case YCMoreLogout:
            cell.imageView.image = [YCIcons close:24 color:[YCTheme nowLine]];
            cell.textLabel.text = @"Выйти";
            cell.textLabel.textColor = [YCTheme nowLine];
            cell.accessoryView = nil;
            break;

        default:
            break;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    /**
     * Каждая ветка в своих скобках: блоки внутри case без них clang считает
     * объявлениями, через которые нельзя перепрыгнуть следующей меткой.
     */
    switch (path.row) {
        case YCMoreCompany: {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:YCShouldChooseCompanyNotification object:nil];
            break;
        }

        case YCMoreStaff: {
            [[YCApi shared] loadStaffWithCompletion:^(NSArray *staff, NSString *error) {
                if (error != nil) {
                    YCAlertMessage(self, @"Сотрудники не получены", error);
                    return;
                }

                NSMutableArray *rows = [NSMutableArray array];

                for (YCStaff *member in staff) {
                    [rows addObject:@[ member.name ?: @"", member.specialization ?: @"" ]];
                }

                [self.navigationController pushViewController:
                    [[YCListController alloc] initWithTitle:@"Сотрудники" rows:rows] animated:YES];
            }];
            break;
        }

        case YCMoreServices: {
            [[YCApi shared] loadServicesForStaff:0 completion:^(NSArray *services, NSString *error) {
                if (error != nil) {
                    YCAlertMessage(self, @"Услуги не получены", error);
                    return;
                }

                NSMutableArray *rows = [NSMutableArray array];

                for (YCService *service in services) {
                    NSString *price = service.price > 0
                        ? [NSString stringWithFormat:@"%.0f ₽", service.price] : @"";

                    [rows addObject:@[ service.title ?: @"", price ]];
                }

                [self.navigationController pushViewController:
                    [[YCListController alloc] initWithTitle:@"Услуги" rows:rows] animated:YES];
            }];
            break;
        }

        case YCMoreAppearance: {
            [self.navigationController pushViewController:[[YCAppearanceController alloc] init]
                                                 animated:YES];
            break;
        }

#ifdef YC_PROXY
        case YCMoreProxy: {
            [self.navigationController pushViewController:[[YCProxyController alloc] init]
                                                 animated:YES];
            break;
        }
#endif

        case YCMoreAbout: {
            [self.navigationController pushViewController:[[YCAboutController alloc] init]
                                                 animated:YES];
            break;
        }

        case YCMoreLogout: {
            YCAlertConfirm(self, @"Выйти из учётной записи?",
                           @"Токен будет удалён с устройства. Записи это не затронет.",
                           @"Выйти", YES, ^{
                [[YCApi shared] logout];
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:YCDidLogOutNotification object:nil];
            });
            break;
        }

        default:
            break;
    }
}

@end


#pragma mark - Список

@implementation YCListController {
    NSArray *_rows;
}

- (id)initWithTitle:(NSString *)title rows:(NSArray *)rows {
    self = [super initWithStyle:UITableViewStylePlain];

    if (self != nil) {
        self.title = title;
        _rows = rows;
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.rowHeight = [YCTheme rowHeight];
    self.tableView.separatorColor = [YCTheme gridLine];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_rows count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    NSArray *row = [_rows objectAtIndex:path.row];

    [YCTheme decorateCell:cell];
    cell.textLabel.text = [row objectAtIndex:0];
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.text = [row objectAtIndex:1];
    cell.detailTextLabel.textColor = [YCTheme mutedText];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    return cell;
}

@end
