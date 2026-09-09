#import "YCAppDelegate.h"

#import "YCApi.h"
#import "YCClientsController.h"
#import "YCDayController.h"
#import "YCIcons.h"
#import "YCLog.h"
#import "YCLoginController.h"
#import "YCExpiry.h"
#import "YCDrawerController.h"
#import "YCMonthController.h"
#import "YCAppearanceController.h"
#import "YCAboutController.h"
#import "YCAlert.h"
#import "YCTheme.h"

/**
 * Корневой контроллер вкладок, который замечает смену системной темы.
 *
 * На iOS 13+ система сообщает о ней через traitCollectionDidChange:. Метод
 * есть с iOS 8, так что на iOS 6 он просто не зовётся. Пересборка экранов
 * идёт только при выборе «как в системе» и только если тёмность правда
 * сменилась: событие приходит и по другим поводам.
 */
@interface YCRootDrawer : YCDrawerController
@property (nonatomic, assign) BOOL wasDark;
@end

@implementation YCRootDrawer

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


@interface YCAppDelegate () <YCLoginControllerDelegate, YCDrawerDelegate>
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
        [self showMain];
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
/**
 * Главный экран: журнал за шторкой.
 *
 * Панели вкладок больше нет. Она стоила сорока девяти точек внизу
 * на каждом экране ради трёх пунктов, а работа идёт с записями, и места
 * не хватало именно им. Шторка занимает ноль, пока закрыта, и вмещает
 * всё, что раньше пряталось во вкладке «Ещё» третьим уровнем.
 */
- (void)showMain {
    YCDayController *journal = [[YCDayController alloc] init];

    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:journal];

    [YCTheme decorateNavigationController:navigation];

    YCRootDrawer *drawer = [[YCRootDrawer alloc] initWithContentController:navigation];

    drawer.drawerDelegate = self;
    drawer.wasDark = [YCTheme isDark];

    self.window.rootViewController = drawer;
    self.window.backgroundColor = [YCTheme background];
}

/**
 * Пункт шторки выбран.
 *
 * «Журнал» ничего не делает нарочно: шторка уже закрылась, и журнал —
 * это то, что под ней. Остальное кладётся поверх журнала, а не заменяет
 * его: вернуться из клиентов в день, на котором остановились, надо
 * одним нажатием «назад», а не выбором пункта заново.
 */
- (void)drawer:(YCDrawerController *)drawer didChooseItem:(YCDrawerItem)item {
    UINavigationController *navigation =
        (UINavigationController *)drawer.contentController;

    if (![navigation isKindOfClass:[UINavigationController class]]) {
        return;
    }

    switch (item) {
        case YCDrawerItemJournal:
            [navigation popToRootViewControllerAnimated:YES];
            break;

        case YCDrawerItemMonth: {
            YCDayController *journal = [[navigation viewControllers] objectAtIndex:0];

            YCMonthController *month =
                [[YCMonthController alloc] initWithDay:journal.day
                                              onChoose:^(NSDate *chosen) {
                [journal goToDay:chosen];
                [navigation popToRootViewControllerAnimated:YES];
            }];

            [navigation pushViewController:month animated:YES];
            break;
        }

        case YCDrawerItemClients:
            [navigation pushViewController:[[YCClientsController alloc] init] animated:YES];
            break;

        case YCDrawerItemAppearance:
            [navigation pushViewController:[[YCAppearanceController alloc] init] animated:YES];
            break;

        case YCDrawerItemAbout:
            [navigation pushViewController:[[YCAboutController alloc] init] animated:YES];
            break;

        case YCDrawerItemCompany:
            [[NSNotificationCenter defaultCenter]
                postNotificationName:YCShouldChooseCompanyNotification object:nil];
            break;

        case YCDrawerItemLogout:
            YCAlertConfirm(navigation, @"Выйти из учётной записи?",
                           @"Токен будет удалён с устройства. Записи это не затронет.",
                           @"Выйти", YES, ^{
                [[YCApi shared] logout];
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:YCDidLogOutNotification object:nil];
            });
            break;

        default:
            break;
    }
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
    [self showMain];
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
    YCDrawerController *drawer = (YCDrawerController *)self.window.rootViewController;

    if (![drawer isKindOfClass:[YCDrawerController class]]) {
        return;
    }

    UINavigationController *navigation =
        (UINavigationController *)drawer.contentController;

    if (![navigation isKindOfClass:[UINavigationController class]]) {
        return;
    }

    UIViewController *root = [[navigation viewControllers] objectAtIndex:0];

    if ([root isKindOfClass:[YCDayController class]]) {
        [(YCDayController *)root reloadAll];
    }
}

@end
