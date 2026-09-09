#import "YCAboutController.h"

#import "YCAlert.h"
#import "YCApi.h"
#import "YCExpiry.h"
#import "YCLog.h"
#import "YCProxy.h"
#import "YCProxyController.h"
#import "YCTls.h"
#import "YCTheme.h"

/** Разделы. */
typedef enum {
    YCAboutSectionApp = 0,
    YCAboutSectionLinks,
    YCAboutSectionProxy,
    YCAboutSectionLog,
    YCAboutSectionCount
} YCAboutSection;

/** Ссылки: заголовок, пояснение, адрес. */
static NSArray *YCAboutLinks(void) {
    return @[
        @[ @"Страница на 4PDA",
           @"обсуждение и новые сборки",
           @"https://4pda.to/forum/index.php?showuser=4458524" ],

        @[ @"Telegram-канал",
           @"@cmplog",
           @"https://t.me/cmplog" ],

        @[ @"Поддержать финансово",
           @"CloudTips",
           @"https://pay.cloudtips.ru/p/83821e32" ]
    ];
}

@implementation YCAboutController {
    NSArray *_sections;         // какие разделы показываем и в каком порядке
}

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"О программе";

    /**
     * Раздел «Отладка» есть только там, где есть сам прокси.
     *
     * В готовой сборке его кода нет вовсе, и раздел показывал бы строку,
     * ведущую на экран с объяснением, почему переключатель не работает.
     * Разделы поэтому перечисляются списком, а не берутся по порядковому
     * номеру: убрать один из середины иначе значит оставить на его месте
     * пустой промежуток.
     */
    NSMutableArray *sections = [NSMutableArray arrayWithObjects:
        [NSNumber numberWithInt:YCAboutSectionApp],
        [NSNumber numberWithInt:YCAboutSectionLinks], nil];

#ifdef YC_PROXY
    [sections addObject:[NSNumber numberWithInt:YCAboutSectionProxy]];
#endif

    [sections addObject:[NSNumber numberWithInt:YCAboutSectionLog]];

    _sections = sections;

    [YCTheme decorateTable:self.tableView color:[YCTheme surface]];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Возвращаемся с экрана прокси — строка состояния должна обновиться.
    [self.tableView reloadData];
}

/** Версия из связки — чтобы не расходилась с той, что в control и Info.plist. */
- (NSString *)version {
    NSString *version = [[[NSBundle mainBundle] infoDictionary]
        objectForKey:@"CFBundleShortVersionString"];

    return [version length] > 0 ? version : @"?";
}

#pragma mark Список

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [_sections count];
}

/** Какой раздел показан под этим номером. */
- (YCAboutSection)sectionAt:(NSInteger)index {
    return (YCAboutSection)[[_sections objectAtIndex:index] intValue];
}

/**
 * Ведётся ли журнал в этой сборке.
 *
 * `make package FINALPACKAGE=1` определяет YC_NO_LOG, и тогда вызовы NSLog
 * выброшены на разборе — журнала нет вовсе, ни файла, ни пути к нему.
 * Отличить такую сборку снаружи можно только по пустому пути, и здесь это
 * и делается: иначе экран показывал бы пустую строку там, где ждут путь,
 * и кнопку «стереть» для того, чего не существует.
 */
- (BOOL)loggingEnabled {
    return [YCLogPath() length] > 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self sectionAt:section]) {
        case YCAboutSectionApp:   return 5;             // название, версия, срок, автор, TLS
        case YCAboutSectionLinks: return [YCAboutLinks() count];
#ifdef YC_PROXY
        case YCAboutSectionProxy: return 1;
#endif
        case YCAboutSectionLog:   return [self loggingEnabled] ? 2 : 1;
        default:                  return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self sectionAt:section]) {
        case YCAboutSectionLinks: return @"Ссылки";
#ifdef YC_PROXY
        case YCAboutSectionProxy: return @"Отладка";
#endif
        case YCAboutSectionLog:   return @"Журнал";
        default:                  return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    YCAboutSection which = [self sectionAt:section];

    if (which == YCAboutSectionLog) {
        if (![self loggingEnabled]) {
            /**
             * Сказать об этом прямо важнее, чем кажется.
             *
             * Молчаливая сборка выглядит точно так же, как сборка со
             * сломанным журналом: файла нет ни в том, ни в другом случае.
             * Разница в том, что искать причину во втором случае негде,
             * а в первом достаточно поставить обычную сборку.
             */
            return @"В этой сборке журнал отключён на этапе компиляции "
                   @"(FINALPACKAGE=1) — файла не будет. Чтобы получить "
                   @"журнал, поставьте обычную сборку: make package ipa";
        }

        /**
         * Как забрать журнал — сказано здесь, а не в переписке.
         *
         * Устройства, на которых это работает, обычно стоят без отладчика
         * и без Xcode рядом; «пришлите лог» без объяснения, откуда его
         * взять, — просьба, которую невозможно выполнить.
         *
         * Про /var/mobile сказано не зря: приложение стоит в /Applications,
         * а не в контейнере App Store, и его Documents — это Documents
         * пользователя, а не отдельная папка приложения. Искать её внутри
         * связки бесполезно, там её нет.
         */
        return @"Полный путь — в строке выше; у приложения из /Applications "
               @"это общая папка пользователя, а не папка внутри связки. "
               @"Открывается любым файловым менеджером (Filza) или по SSH.";
    }

    if (which == YCAboutSectionApp) {
        return @"Журнал записей YClients для iOS 6 и новее. "
               @"Работает поверх cYclients — библиотеки на C.";
    }

    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                               reuseIdentifier:nil];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [YCTheme decorateCell:cell];

    // Цвета задаются каждой ячейке явно: по умолчанию UITableViewCell
    // красит подпись тёмно-серым, и в тёмной теме путь к журналу
    // оказывался чёрным по чёрному — на видео его было не прочесть.
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.font = [YCTheme bodyFont];
    cell.detailTextLabel.textColor = [YCTheme mutedText];

    switch ([self sectionAt:path.section]) {
        case YCAboutSectionApp:
            [self fillAppCell:cell row:path.row];
            break;

        case YCAboutSectionLinks:
            [self fillLinkCell:cell row:path.row];
            break;

#ifdef YC_PROXY
        case YCAboutSectionProxy:
            [self fillProxyCell:cell];
            break;
#endif

        case YCAboutSectionLog:
            [self fillLogCell:cell row:path.row];
            break;

        default:
            break;
    }

    return cell;
}

- (void)fillAppCell:(UITableViewCell *)cell row:(NSInteger)row {
    switch (row) {
        case 0:
            cell.textLabel.text = @"Приложение";
            cell.detailTextLabel.text = @"YClients";
            break;

        case 1:
            cell.textLabel.text = @"Версия";
            cell.detailTextLabel.text = [self version];
            break;

        case 2: {
            /**
             * Срок сборки — рядом с версией, где его и станут искать.
             *
             * На экране входа он тоже есть, но туда попадают один раз,
             * а сюда заходят, когда что-то перестало работать.
             */
            cell.textLabel.text = @"Срок";

            if (![YCExpiry isLimited]) {
                cell.detailTextLabel.text = @"без ограничения";
                break;
            }

            cell.detailTextLabel.text = [YCExpiry isExpired] ? @"истёк" : [YCExpiry notice];
            cell.detailTextLabel.textColor = [YCExpiry isExpired] ? [YCTheme nowLine]
                                                                  : [YCTheme mutedText];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
            cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
            cell.detailTextLabel.minimumScaleFactor = 0.6;
            break;
        }

        case 3:
            cell.textLabel.text = @"Разработчик";
            cell.detailTextLabel.text = @"Computershik";
            break;

        case 4:
            /**
             * Строка про TLS здесь не для красоты.
             *
             * Приложение ходит в сеть на своей криптографии, а не системной,
             * и когда сервер вдруг перестанет отвечать, первый вопрос —
             * поднялась ли она и сколько корней прочиталось. Ноль корней
             * означает, что проверка сертификата провалится на любом сервере.
             */
            cell.textLabel.text = @"Шифрование";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, корней %ld",
                                         [YCTls libraryVersion], (long)[YCTls loadedRootCount]];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
            cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
            cell.detailTextLabel.minimumScaleFactor = 0.6;
            break;

        default:
            break;
    }
}

- (void)fillLinkCell:(UITableViewCell *)cell row:(NSInteger)row {
    NSArray *link = [YCAboutLinks() objectAtIndex:row];

    cell.textLabel.text = [link objectAtIndex:0];
    cell.textLabel.textColor = [YCTheme accent];

    cell.detailTextLabel.text = [link objectAtIndex:1];
    cell.detailTextLabel.textColor = [YCTheme mutedText];

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

#ifdef YC_PROXY

/** Строка состояния прокси; сама настройка — на отдельном экране. */
- (void)fillProxyCell:(UITableViewCell *)cell {
    cell.textLabel.text = @"Прокси для отладки";
    cell.detailTextLabel.text = [YCProxy summary];

    // Включённый подсвечен: он снимает проверку сертификата, и забыть
    // о нём после отладки не должно быть легко.
    cell.detailTextLabel.textColor = [YCProxy isActive] ? [YCTheme nowLine]
                                                        : [YCTheme mutedText];

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

#endif  /* YC_PROXY */

- (void)fillLogCell:(UITableViewCell *)cell row:(NSInteger)row {
    if (row == 0) {
        if (![self loggingEnabled]) {
            cell.textLabel.text = @"Журнал";
            cell.detailTextLabel.text = @"отключён";
            cell.detailTextLabel.textColor = [YCTheme mutedText];
            return;
        }

        cell.textLabel.text = @"Файл";

        /**
         * Путь целиком, мелким шрифтом и в одну строку.
         *
         * Он длинный — в нём номер связки, — и подогнать его под ширину
         * ячейки лучше, чем обрезать: обрезанный путь бесполезен, а мелкий
         * читается, если поднести телефон к глазам.
         */
        cell.detailTextLabel.text = YCLogPath();
        cell.detailTextLabel.font = [UIFont systemFontOfSize:10.0];
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.minimumScaleFactor = 0.5;
        return;
    }

    cell.textLabel.text = @"Стереть журнал";
    cell.textLabel.textColor = [YCTheme nowLine];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

#pragma mark Нажатия

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    YCAboutSection which = [self sectionAt:path.section];

#ifdef YC_PROXY
    if (which == YCAboutSectionProxy) {
        [self.navigationController pushViewController:[[YCProxyController alloc] init]
                                             animated:YES];
        return;
    }
#endif

    if (which == YCAboutSectionLinks) {
        NSArray *link = [YCAboutLinks() objectAtIndex:path.row];

        [self openAddress:[link objectAtIndex:2] named:[link objectAtIndex:0]];
        return;
    }

    if (which == YCAboutSectionLog && path.row == 1) {
        YCAlertConfirm(self, @"Стереть журнал?",
                       @"Файл будет удалён. Записи YClients это не затронет.",
                       @"Стереть", YES, ^{
            YCLogClear();

            NSLog(@"[YClients] Журнал стёрт из «О программе»");
        });
    }
}

/**
 * Открывает ссылку в браузере.
 *
 * `openURL:` без вариантов, хотя с iOS 10 он помечен устаревшим: у нового
 * `openURL:options:completionHandler:` в SDK 9.3 нет объявления вовсе,
 * и позвать его можно было бы только через NSInvocation — три строки
 * ради того же самого. Устаревшим он помечен, но не убран ни в одной
 * версии, а нижняя граница у нас там, где нового ещё нет.
 */
- (void)openAddress:(NSString *)address named:(NSString *)name {
    NSURL *url = [NSURL URLWithString:address];

    UIApplication *application = [UIApplication sharedApplication];

    if (url == nil || ![application canOpenURL:url]) {
        /**
         * Отказ здесь не редкость и не поломка.
         *
         * `tg://`-обработчика может не быть, а на iOS 6 без установленного
         * браузера ссылку открывать нечем. Показать адрес текстом — то, что
         * в этом случае реально помогает: его можно переписать руками.
         */
        YCAlertMessage(self, name, address);
        return;
    }

    NSLog(@"[YClients] Открываем %@", address);

    [application openURL:url];
}

@end
