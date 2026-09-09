#import "YCAppDelegate.h"

#import "YCApi.h"
#import "YCClientsController.h"
#import "YCDayController.h"
#import "YCIcons.h"
#import "YCLog.h"
#import "YCLoginController.h"
#import "YCExpiry.h"
#import "YCTheme.h"

/**
 * Корневой контроллер вкладок, который замечает смену системной темы.
 *
 * На iOS 13+ система сообщает о ней через traitCollectionDidChange:. Метод
 * есть с iOS 8, так что на iOS 6 он просто не зовётся. Пересборка экранов
 * идёт только при выборе «как в системе» и только если тёмность правда
 * сменилась: событие приходит и по другим поводам.
 */
@interface YCTabsController : UITabBarController
@property (nonatomic, assign) BOOL wasDark;
@end

@implementation YCTabsController

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];

    if ([YCTheme appearance] != YCAppearanceSystem) {
        return;
    }

    if ([YCTheme isDark] != self.wasDark) {
        NSLog(@"[YClients/Тема] Система сменила тему");

        [YCTheme applyAppearance];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:YCAppearanceDidChangeNotification object:nil];
    }
}

@end


@interface YCAppDelegate () <YCLoginControllerDelegate>
@end

@implementation YCAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSLog(@"[YClients] Запуск. Вход выполнен: %@, филиал: %ld «%@»",
          [[YCApi shared] isAuthorized] ? @"да" : @"нет",
          (long)[[YCApi shared] companyId],
          [[YCApi shared] companyTitle]);

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [YCTheme background];

    // После создания окна: applyAppearance ставит ему тему на iOS 13+.
    [YCTheme applyAppearance];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAppearanceChange)
                                                 name:YCAppearanceDidChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLogOut)
                                                 name:YCDidLogOutNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleChooseCompany)
                                                 name:YCShouldChooseCompanyNotification
                                               object:nil];

    [self showStartingScreen];

    [self.window makeKeyAndVisible];

    return YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/**
 * Куда попадает пользователь при запуске.
 *
 * Токен и филиал хранятся между запусками, поэтому обычный запуск ведёт
 * прямо в журнал. Проверки токена на живость нет намеренно: отозванный
 * токен виден по первому же запросу.
 */
- (void)showStartingScreen {
    /**
     * Просроченная сборка не идёт дальше экрана входа.
     *
     * Ни токен, ни выбранный филиал при этом не трогаются: срок — повод
     * не работать, а не повод стирать чужие настройки. Поставят свежую
     * сборку — всё окажется на месте.
     */
    if ([YCExpiry isExpired]) {
        NSLog(@"[YClients] Срок сборки истёк, работа прекращена");

        [self showLoginStartingAtCompanies:NO];
        return;
    }

    if ([[YCApi shared] isAuthorized] && [[YCApi shared] companyId] != 0) {
        [self showTabs];
        return;
    }

    [self showLoginStartingAtCompanies:([[YCApi shared] isAuthorized] &&
                                        [[YCApi shared] companyId] == 0)];
}

/**
 * Три вкладки из пяти оригинальных.
 *
 * «График» и «Уведомления» держатся на эндпойнтах расписания и уведомлений,
 * которых в библиотеке нет. Вкладка, за которой пусто, хуже её отсутствия:
 * она обещает то, чего нет.
 */
- (void)showTabs {
    UIColor *ink = [YCTheme text];

    UINavigationController *journal = [[UINavigationController alloc]
        initWithRootViewController:[[YCDayController alloc] init]];
    [YCTheme decorateNavigationController:journal];
    journal.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Журнал"
                                                       image:[YCIcons calendar:26 color:ink]
                                                         tag:0];

    UINavigationController *clients = [[UINavigationController alloc]
        initWithRootViewController:[[YCClientsController alloc] init]];
    [YCTheme decorateNavigationController:clients];
    clients.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Клиенты"
                                                       image:[YCIcons people:26 color:ink]
                                                         tag:1];

    UINavigationController *more = [[UINavigationController alloc]
        initWithRootViewController:[[YCMoreController alloc] init]];
    [YCTheme decorateNavigationController:more];
    more.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Ещё"
                                                    image:[YCIcons menu:26 color:ink]
                                                      tag:2];

    YCTabsController *tabs = [[YCTabsController alloc] init];

    tabs.viewControllers = @[ journal, clients, more ];
    tabs.wasDark = [YCTheme isDark];

    [YCTheme decorateTabBar:tabs.tabBar];

    self.window.rootViewController = tabs;
    self.window.backgroundColor = [YCTheme background];
}

/**
 * Смена темы — пересборка корневого экрана.
 *
 * Все цвета читаются при создании видов, и проще создать их заново, чем
 * обходить и перекрашивать. Открытая вкладка сохраняется; всё, что было
 * выше по навигации — форма, карточка, — закрывается: смена темы — редкое
 * действие, и делают его не посреди заполнения записи.
 */
- (void)handleAppearanceChange {
    UITabBarController *tabs = (UITabBarController *)self.window.rootViewController;

    if ([tabs isKindOfClass:[UITabBarController class]]) {
        NSUInteger selected = tabs.selectedIndex;

        [self showTabs];

        // Возвращаемся в «Ещё» — туда, где тему и выбирали.
        [(UITabBarController *)self.window.rootViewController setSelectedIndex:selected];
        return;
    }

    [self showStartingScreen];
}

- (void)showLoginStartingAtCompanies:(BOOL)atCompanies {
    UIViewController *root;

    if (atCompanies) {
        YCCompaniesController *companies = [[YCCompaniesController alloc] init];

        companies.delegate = self;
        companies.explicitChoice = YES;
        root = companies;
    } else {
        YCLoginController *login = [[YCLoginController alloc] init];

        login.delegate = self;
        root = login;
    }

    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:root];

    [YCTheme decorateNavigationController:navigation];

    self.window.rootViewController = navigation;
}

#pragma mark Смена экрана

- (void)handleLogOut {
    [self showLoginStartingAtCompanies:NO];
}

- (void)handleChooseCompany {
    [self showLoginStartingAtCompanies:YES];
}

- (void)loginControllerDidFinish:(id)controller {
    [self showTabs];
}

#pragma mark Возврат в приложение

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Срок мог истечь, пока приложение лежало свёрнутым.
    if ([YCExpiry isExpired]) {
        [self showStartingScreen];
        return;
    }

    // Журнал перечитывается при возвращении: записи заводят и в вебе,
    // и день, показанный два часа назад, к возврату уже неверен.
    UITabBarController *tabs = (UITabBarController *)self.window.rootViewController;

    if (![tabs isKindOfClass:[UITabBarController class]]) {
        return;
    }

    UINavigationController *journal = [tabs.viewControllers objectAtIndex:0];
    UIViewController *top = [journal topViewController];

    if ([top isKindOfClass:[YCDayController class]]) {
        [(YCDayController *)top reloadAll];
    }
}

@end
