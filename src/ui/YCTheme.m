#import "YCTheme.h"

#import <QuartzCore/QuartzCore.h>

NSString *const YCAppearanceDidChangeNotification = @"YCAppearanceDidChange";

static NSString *const YCAppearanceKey = @"appearance";

static UIColor *YCRGB(int hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1.0];
}

/** Светлое или тёмное значение — по текущей теме. */
static UIColor *YCPick(int light, int dark) {
    return YCRGB([YCTheme isDark] ? dark : light);
}

/**
 * Подложка: вид, чей собственный слой — градиент.
 *
 * Растягиваемой картинкой, как у кнопок, здесь не обойтись: девятичастное
 * растяжение повторяет одну среднюю строку, и вертикальный градиент
 * вырождается в полосу посередине. У кнопок это незаметно, потому что
 * они невысокие и кайма занимает почти всю высоту, а у панели в пол-экрана
 * получилась бы заливка с ободком.
 *
 * Слой градиента, подставленный через layerClass, растягивается вместе
 * с видом сам — авторазметка вида работает, в отличие от авторазметки
 * отдельно добавленного слоя.
 */
@interface YCSkinView : UIView
@end

@implementation YCSkinView

+ (Class)layerClass {
    return [CAGradientLayer class];
}

@end

/** Внутренние помощники: объявлены заранее, потому что зовутся выше по файлу. */
@interface YCTheme ()

+ (BOOL)systemDrawsLists;
+ (UIImage *)glossImageWithColor:(UIColor *)color radius:(CGFloat)radius sunken:(BOOL)sunken;
+ (void)skin:(UIView *)view color:(UIColor *)color radius:(CGFloat)radius sunken:(BOOL)sunken;

@end

@implementation YCTheme

#pragma mark Тема

+ (YCAppearance)appearance {
    NSInteger stored = [[NSUserDefaults standardUserDefaults] integerForKey:YCAppearanceKey];

    return (stored >= 0 && stored <= 2) ? (YCAppearance)stored : YCAppearanceSystem;
}

+ (void)setAppearance:(YCAppearance)appearance {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setInteger:appearance forKey:YCAppearanceKey];
    [defaults synchronize];

    NSLog(@"[YClients/Тема] Выбрано: %ld, тёмная: %@",
          (long)appearance, [self isDark] ? @"да" : @"нет");

    [self applyAppearance];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:YCAppearanceDidChangeNotification object:nil];
}

+ (BOOL)systemIsDark {
    UIScreen *screen = [UIScreen mainScreen];

    // traitCollection у экрана есть с iOS 8, userInterfaceStyle — с iOS 12,
    // а тёмное значение (2) появляется в iOS 13. Всё через проверки и KVC:
    // ни одного имени, которого нет в SDK 9.3.
    if (![screen respondsToSelector:@selector(traitCollection)]) {
        return NO;
    }

    id traits = [screen traitCollection];

    @try {
        NSNumber *style = [traits valueForKey:@"userInterfaceStyle"];

        return [style integerValue] == 2;   // UIUserInterfaceStyleDark
    }
    @catch (NSException *e) {
        return NO;
    }
}

+ (BOOL)isDark {
    switch ([self appearance]) {
        case YCAppearanceDark:  return YES;
        case YCAppearanceLight: return NO;
        default:                return [self systemIsDark];
    }
}

#pragma mark Цвета

/**
 * Палитра снята со снимков приложения YClients для Android; тёмная —
 * по тем же правилам: чёрный фон, серые подложки, тот же жёлтый.
 * Жёлтый на тёмном ярче кажется, но менять его нельзя — по нему
 * приложение и узнают.
 */
+ (UIColor *)background   { return YCPick(0xFFFFFF, 0x121214); }
+ (UIColor *)surface      { return YCPick(0xF5F6F8, 0x1E1E22); }
/**
 * Подложка сетки дня.
 *
 * На iOS 6 в светлой теме — чуть темнее белого. Сетка это не панель,
 * а поверхность, на которой лежат записи; когда она того же цвета, что
 * шапка и шкала, всё вместе читается одним белым листом с ниточками
 * линий. Полтона разницы достаточно, чтобы шапка стала приподнятой,
 * а сетка — углублением.
 */
+ (UIColor *)gridPaper {
    return ([self isLegacy] && ![self isDark]) ? YCRGB(0xF2F1ED) : [self background];
}

+ (UIColor *)gridLine     { return YCPick(0xE3E5E8, 0x2E2E33); }
+ (UIColor *)gridLineFaint{ return YCPick(0xF0F1F3, 0x1C1C20); }
+ (UIColor *)text         { return YCPick(0x1C1C1E, 0xF2F2F4); }
+ (UIColor *)mutedText    { return YCPick(0x8C8C91, 0x9A9AA0); }
+ (UIColor *)accent       { return YCRGB(0xFFC800); }
+ (UIColor *)nowLine      { return YCRGB(0xE8402A); }
+ (UIColor *)border       { return YCPick(0xE3E5E8, 0x37373C); }
+ (UIColor *)darkPanel    { return YCPick(0x2A2A2C, 0x2A2A2E); }
+ (UIColor *)weekend      { return YCRGB(0xE85A32); }

+ (UIColor *)closedHours {
    return [YCPick(0xE9ECEF, 0x1A1A1E) colorWithAlphaComponent:0.55];
}

static UIColor *YCColorFromHex(NSString *string) {
    NSString *hex = [string stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"# \t"]];

    if ([hex length] != 6) {
        return nil;
    }

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];

    if (![scanner scanHexInt:&value] || ![scanner isAtEnd]) {
        return nil;
    }

    return YCRGB((int)value);
}

+ (NSString *)hexFromColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;

    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        return @"";
    }

    return [NSString stringWithFormat:@"%02x%02x%02x",
            (int)round(r * 255), (int)round(g * 255), (int)round(b * 255)];
}

/**
 * Цвет полосы состояния — как в самом YClients.
 *
 * Значения сервера: 0 — записан, 2 — подтвердил, 1 — пришёл, -1 — не пришёл.
 * Цвета к ним заказчик назвал прямо, и своевольничать тут нельзя: по этим
 * четырём цветам администратор читает день одним взглядом, не вчитываясь
 * в подписи, и любой другой набор ломает привычку.
 *
 * Жёлтый взят темнее фирменного: фирменный стоит на кнопках, и запись
 * «пришёл» не должна выглядеть кнопкой.
 */
+ (UIColor *)statusColorForAttendance:(NSInteger)attendance {
    switch (attendance) {
        case 2:  return YCRGB(0x8E44AD);   // подтвердил — фиолетовый
        case 1:  return YCRGB(0xE8A00C);   // пришёл — жёлтый
        case -1: return YCRGB(0xE8402A);   // не пришёл — красный
        default: return YCRGB(0x2E9E5B);   // записан — зелёный
    }
}

+ (UIColor *)recordColorForAttendance:(NSInteger)attendance
                         customColor:(NSString *)customColor {
    UIColor *custom = YCColorFromHex(customColor);

    if (custom != nil) {
        return custom;
    }

    CGFloat r = 0, g = 0, b = 0, a = 0;

    [[self statusColorForAttendance:attendance] getRed:&r green:&g blue:&b alpha:&a];

    // Тело — оттенок статуса: к белому в светлой теме, к чёрному в тёмной.
    // Иначе бледно-зелёный прямоугольник на чёрном светился бы как фонарь.
    if ([self isDark]) {
        return [UIColor colorWithRed:r * 0.45 green:g * 0.45 blue:b * 0.45 alpha:1.0];
    }

    return [UIColor colorWithRed:r + (1 - r) * 0.62
                           green:g + (1 - g) * 0.62
                            blue:b + (1 - b) * 0.62
                           alpha:1.0];
}

+ (UIColor *)textColorOnColor:(UIColor *)color {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;

    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return [UIColor whiteColor];
    }

    CGFloat luma = 0.299 * red + 0.587 * green + 0.114 * blue;

    return luma > 0.62 ? YCRGB(0x1C1C1E) : [UIColor whiteColor];
}

+ (NSArray *)recordPalette {
    return @[ @"", @"7B5A45", @"FF4A3D", @"E5245F", @"9C27B0",
              @"5B3FBF", @"2F4FB3", @"2196F3", @"00B0F0", @"00BFA5",
              @"2E9E5B", @"8BC34A", @"FFB300", @"FF7A00" ];
}

#pragma mark Размеры

/**
 * Тесный ли экран — 320 точек в ширину.
 *
 * Это iPhone 4, 4S, 5, 5s, SE первого поколения — то есть ровно те, ради
 * которых всё и затевалось. Снимки оригинала сняты с экрана в 400 с лишним
 * точек, и перенесённые с них размеры на 320 выглядят крупнее, чем задумано:
 * в сетку помещается четыре часа вместо шести, а форма записи не влезает
 * на экран целиком.
 *
 * Берётся наименьшая сторона, а не ширина: в положении лёжа ширина другая,
 * а плотность экрана та же, и размеры не должны прыгать при повороте.
 */
+ (BOOL)isCompact {
    CGSize screen = [UIScreen mainScreen].bounds.size;

    return MIN(screen.width, screen.height) <= 320.0;
}

/** Значение для тесного экрана и для обычного. */
static CGFloat YCSize(CGFloat compact, CGFloat regular) {
    return [YCTheme isCompact] ? compact : regular;
}

+ (CGFloat)rulerWidth     { return YCSize(44.0, 52.0); }
+ (CGFloat)headerHeight   { return YCSize(66.0, 78.0); }
+ (CGFloat)hourHeight     { return YCSize(56.0, 64.0); }
+ (CGFloat)minColumnWidth { return YCSize(104.0, 120.0); }
+ (CGFloat)rowHeight      { return YCSize(48.0, 54.0); }
+ (CGFloat)formRowHeight  { return YCSize(54.0, 62.0); }
+ (CGFloat)avatarSize     { return YCSize(32.0, 38.0); }

+ (NSTimeInterval)timeStep { return 15 * 60; }

#pragma mark Шрифты

+ (UIFont *)recordTitleFont  { return [UIFont systemFontOfSize:YCSize(10.0, 11.0)]; }
+ (UIFont *)recordDetailFont { return [UIFont boldSystemFontOfSize:YCSize(10.0, 11.0)]; }
+ (UIFont *)rulerFont        { return [UIFont systemFontOfSize:YCSize(11.0, 12.0)]; }
+ (UIFont *)headerFont       { return [UIFont systemFontOfSize:YCSize(11.0, 12.0)]; }
+ (UIFont *)titleFont        { return [UIFont boldSystemFontOfSize:YCSize(15.0, 16.0)]; }
+ (UIFont *)bodyFont         { return [UIFont systemFontOfSize:YCSize(14.0, 15.0)]; }
+ (UIFont *)rowFont          { return [UIFont systemFontOfSize:YCSize(15.0, 16.0)]; }
+ (UIFont *)captionFont      { return [UIFont systemFontOfSize:YCSize(11.0, 12.0)]; }

#pragma mark Оформление панелей

+ (void)applyAppearance {
    BOOL dark = [self isDark];

    UIColor *background = [self background];
    UIColor *text = [self text];

    /**
     * Панель навигации и вкладок.
     *
     * Ключи разные по версиям. На iOS 7+ фон панели задаёт barTintColor,
     * tintColor красит кнопки. На iOS 6 barTintColor нет, а tintColor красит
     * саму панель. Тёмная панель на iOS 6 ещё и просит barStyle: без него
     * поверх тёмного фона рисуется светлый глянец.
     */
    UINavigationBar *bar = [UINavigationBar appearance];

    if ([bar respondsToSelector:@selector(setBarTintColor:)]) {
        [bar setBarTintColor:background];
        [bar setTintColor:text];
        [bar setBarStyle:(dark ? UIBarStyleBlack : UIBarStyleDefault)];
    } else {
        [bar setTintColor:(dark ? YCRGB(0x1E1E22) : YCRGB(0xF2F2F2))];
    }

    [bar setTitleTextAttributes:@{
        UITextAttributeTextColor: text,
        UITextAttributeFont: [self titleFont],
        UITextAttributeTextShadowColor: [UIColor clearColor]
    }];

    UITabBar *tabs = [UITabBar appearance];

    if ([tabs respondsToSelector:@selector(setBarTintColor:)]) {
        [tabs setBarTintColor:background];
        [tabs setTintColor:text];
        [tabs setBarStyle:(dark ? UIBarStyleBlack : UIBarStyleDefault)];
    } else {
        /**
         * На iOS 6 панель вкладок тёмная — и в светлой теме тоже.
         *
         * Светлой я её сделал зря. Система рисует её содержимое из расчёта
         * на тёмный фон: значок берётся только по прозрачности и заливается
         * системным серым, подпись выбранной вкладки — белым, а под ней
         * лежит светлое пятно-подсветка. На белой панели белая подпись
         * пропадала совсем, и выбранную вкладку нельзя было прочесть.
         *
         * Перекрасить подпись можно, но правильнее не спорить с системой:
         * белая панель навигации сверху и тёмная панель вкладок снизу —
         * обычный вид приложения тех лет.
         */
        [tabs setTintColor:YCRGB(0x1C1C1E)];
        [tabs setSelectedImageTintColor:[self accent]];

        // Подписи задаются явно, чтобы не зависеть от того, каким серым
        // система решит их нарисовать: невыбранные приглушённые, выбранная
        // фирменным жёлтым — в цвет значка.
        UITabBarItem *item = [UITabBarItem appearance];

        [item setTitleTextAttributes:@{
            UITextAttributeTextColor: YCRGB(0x9A9A9E),
            UITextAttributeTextShadowColor: [UIColor clearColor]
        } forState:UIControlStateNormal];

        [item setTitleTextAttributes:@{
            UITextAttributeTextColor: [self accent],
            UITextAttributeTextShadowColor: [UIColor clearColor]
        } forState:UIControlStateSelected];
    }

    /**
     * Списки: фон и текст ячеек по умолчанию.
     *
     * До iOS 13 ячейка всегда белая с чёрным текстом, и тёмная тема
     * без этого была бы белыми полосами на чёрном. UIAppearance не трогает
     * то, что задано на экземпляре напрямую, — так что цвета, выставленные
     * в контроллерах, остаются в силе.
     */
    if (![self systemDrawsLists]) {
        [[UITableView appearance] setBackgroundColor:background];
        [[UITableViewCell appearance] setBackgroundColor:background];
        [[UILabel appearanceWhenContainedIn:[UITableViewCell class], nil] setTextColor:text];
        [[UITableView appearance] setSeparatorColor:[self gridLine]];
    }

    /**
     * Строка состояния.
     *
     * Стилем распоряжается приложение (UIViewControllerBasedStatusBarAppearance
     * в Info.plist выключен), и один вызов действует от iOS 6 до нынешних.
     * Значения: на iOS 6 тёмная полоса это BlackOpaque (2); с iOS 7 белый
     * текст это LightContent (1), а Default (0) подстраивается под окно.
     */
    UIApplication *application = [UIApplication sharedApplication];
    BOOL modern = [[UIDevice currentDevice].systemVersion floatValue] >= 7.0;
    UIStatusBarStyle style = dark ? (modern ? (UIStatusBarStyle)1 : (UIStatusBarStyle)2)
                                  : UIStatusBarStyleDefault;

    [application setStatusBarStyle:style animated:NO];

    /**
     * Окно — под ту же тему на iOS 13+.
     *
     * overrideUserInterfaceStyle заставляет системные вещи — окна сообщений,
     * клавиатуру, колёса — следовать нашему выбору, а не системному. Свойства
     * нет в SDK 9.3, отсюда KVC; значения: 0 — как у системы, 1 — светлая,
     * 2 — тёмная.
     */
    UIWindow *window = [[application delegate] window];

    if ([window respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
        NSInteger override = 0;

        switch ([self appearance]) {
            case YCAppearanceLight: override = 1; break;
            case YCAppearanceDark:  override = 2; break;
            default:                override = 0; break;
        }

        [window setValue:@(override) forKey:@"overrideUserInterfaceStyle"];
    }
}

#pragma mark Панели у конкретных видов

/**
 * Общее для обеих панелей: непрозрачность и цвет.
 *
 * translucent выключается **до** barTintColor намеренно. Пока панель
 * прозрачна, система рисует её как размытие того, что под ней; цвет при
 * этом лишь подкрашивает размытие, и тёмный превращается в светло-серый.
 * Ровно это и было видно на iOS 7: чёрная сетка под светлыми панелями.
 */
static void YCDecorateBar(id bar, BOOL dark, UIColor *background, UIColor *ink) {
    if ([bar respondsToSelector:@selector(setTranslucent:)]) {
        [bar setTranslucent:NO];
    }

    if ([bar respondsToSelector:@selector(setBarTintColor:)]) {
        [bar setBarTintColor:background];
        [bar setTintColor:ink];
    } else {
        /**
         * iOS 6: barTintColor ещё нет, а tintColor красит саму панель.
         *
         * И красить её в чистый белый нельзя. Система накладывает на панель
         * свой глянец — светлую дугу поверху, — а по белому он не виден
         * вовсе: панель выходит ровной заливкой, ничем не отличимой от
         * листа под ней. Полутон серого возвращает и глянец, и границу
         * между панелью и содержимым.
         *
         * Тот же цвет стоит в applyAppearance; здесь он повторён, потому
         * что вызов для конкретной панели идёт позже и перекрывает общий.
         */
        [bar setTintColor:(dark ? YCRGB(0x1E1E22) : YCRGB(0xF2F2F2))];
    }

    /**
     * barStyle у панели вкладок появился только в iOS 7.
     *
     * У панели навигации это свойство с версии 2.0, и одной строкой на обе
     * панели оно писалось безнаказанно ровно до тех пор, пока приложение
     * не запустили на шестёрке: там выбор филиала вёл к панели вкладок,
     * и она падала на «нераспознанном селекторе».
     *
     * Компилятор об этом не предупредил и не мог: bar объявлен как id,
     * а по нему не видно, у какого именно класса спрашивать, когда
     * свойство появилось. Проверка по самому свойству — единственный
     * способ, работающий для обеих панелей сразу.
     */
    if ([bar respondsToSelector:@selector(setBarStyle:)]) {
        [bar setBarStyle:(dark ? UIBarStyleBlack : UIBarStyleDefault)];
    }
}

+ (void)decorateNavigationController:(UINavigationController *)navigation {
    BOOL dark = [self isDark];

    YCDecorateBar(navigation.navigationBar, dark, [self background], [self text]);

    /**
     * На iOS 6 кнопки панели остаются выпуклыми — и это здесь нарочно.
     *
     * Раньше я подсовывал им пустую картинку фона, чтобы стало плоско:
     * «Назад» была серой пилюлей посреди белой панели, и это выглядело
     * чужеродно. Но чужеродной её делала не выпуклость, а цвет — плашку
     * система красила своим синим по умолчанию, мимо всей остальной темы.
     * Плоская же кнопка среди выпуклой клавиатуры и панелей 2012 года
     * читается не как «современно», а как «не дорисовано».
     *
     * Поэтому плашка возвращается, но окрашивается в фирменный жёлтый,
     * а надпись на ней — тёмная, как на жёлтых кнопках экранов.
     */
    if ([self isLegacy]) {
        UIBarButtonItem *item = [UIBarButtonItem appearance];

        [item setTintColor:[self accent]];

        [item setTitleTextAttributes:@{
            UITextAttributeTextColor: [self text],
            UITextAttributeFont: [self bodyFont],
            UITextAttributeTextShadowColor: [UIColor clearColor]
        } forState:UIControlStateNormal];
    }

    [navigation.navigationBar setTitleTextAttributes:@{
        UITextAttributeTextColor: [self text],
        UITextAttributeFont: [self titleFont],
        UITextAttributeTextShadowColor: [UIColor clearColor]
    }];

    navigation.view.backgroundColor = [self background];
}

+ (void)decorateTabBar:(UITabBar *)bar {
    if ([self isLegacy]) {
        // Тёмная панель — см. пояснение в applyAppearance.
        [bar setTintColor:YCRGB(0x1C1C1E)];
        [bar setSelectedImageTintColor:[self accent]];

        return;
    }

    YCDecorateBar(bar, [self isDark], [self background], [self text]);
}

+ (void)decorateSearchBar:(UISearchBar *)bar {
    BOOL dark = [self isDark];

    bar.barStyle = dark ? UIBarStyleBlack : UIBarStyleDefault;

    /**
     * keyboardAppearance у строки поиска есть только с iOS 7.
     *
     * У UITextField это свойство с iOS 3.2, и я перенёс строку по аналогии —
     * а UISearchBar обзавёлся им на четыре года позже. На iOS 6 приложение
     * падало здесь с «нераспознанным селектором» при открытии списка
     * филиалов; до этого экрана на шестёрке просто ни разу не доходили,
     * потому что вход обрывался по времени.
     */
    if ([bar respondsToSelector:@selector(setKeyboardAppearance:)]) {
        [bar setKeyboardAppearance:[self keyboardAppearance]];
    }

    if ([bar respondsToSelector:@selector(setBarTintColor:)]) {
        [bar setBarTintColor:[self background]];
        [bar setTintColor:[self accent]];
    }
}

+ (void)decoratePicker:(UIView *)picker {
    // На iOS 13 и новее цвет держит окно; трогать там нечего.
    if ([picker respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
        return;
    }

    if (![self isDark]) {
        return;
    }

    /**
     * textColor у UIPickerView и UIDatePicker существует, но не объявлен
     * в заголовках: до iOS 14 это открытое свойство, потом его перестали
     * показывать. Отсюда setValue:forKey: и защита от исключения — если
     * ключа не окажется, надписи просто останутся тёмными, а не уронят
     * приложение.
     */
    @try {
        [picker setValue:[self text] forKey:@"textColor"];
    }
    @catch (NSException *exception) {
        NSLog(@"[YClients/Тема] Колесу не задать цвет: %@", exception.name);
    }
}

+ (UIActivityIndicatorViewStyle)spinnerStyle {
    return [self isDark] ? UIActivityIndicatorViewStyleWhite
                         : UIActivityIndicatorViewStyleGray;
}

+ (UIKeyboardAppearance)keyboardAppearance {
    return [self isDark] ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
}

#pragma mark Скевоморфизм

+ (BOOL)isLegacy {
    // По наличию barTintColor, а не по номеру версии: это свойство появилось
    // ровно вместе с плоским оформлением, и другой границы искать незачем.
    return ![[UINavigationBar appearance] respondsToSelector:@selector(setBarTintColor:)];
}

+ (CGFloat)cornerRadius { return [self isLegacy] ? 8.0 : 16.0; }
+ (CGFloat)buttonRadius { return [self isLegacy] ? 10.0 : 26.0; }

+ (void)decorateField:(UITextField *)field {
    field.font = [self bodyFont];
    field.textColor = [self text];
    field.keyboardAppearance = [self keyboardAppearance];

    if ([self isLegacy]) {
        /**
         * Системный бортик — и никаких своих отступов.
         *
         * UITextBorderStyleRoundedRect рисует ту самую вдавленную рамку
         * со скосом, которой на iOS 6 выглядят все поля ввода, и сам
         * расставляет текст внутри неё. Прежняя вёрстка добавляла слева
         * пустой вид высотой в десять точек — а на iOS 6 высота leftView
         * задаёт и вертикаль, отчего подпись съезжала к верхнему краю.
         */
        field.borderStyle = UITextBorderStyleRoundedRect;
        field.leftView = nil;
        field.layer.borderWidth = 0.0;
        field.layer.cornerRadius = 0.0;
        field.backgroundColor = [UIColor clearColor];

        /**
         * В тёмной теме текст здесь всё равно тёмный.
         *
         * Системный бортик — картинка со светлой заливкой, и перекрасить
         * её нельзя. Белые буквы легли бы на белое поле. Сама iOS 6 ведёт
         * себя так же: её поля ввода остаются светлыми и на чёрных панелях.
         */
        field.textColor = [UIColor blackColor];

        return;
    }

    field.borderStyle = UITextBorderStyleNone;
    field.backgroundColor = [self background];
    field.layer.cornerRadius = [self cornerRadius];
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = [self border].CGColor;

    // Отступ слева — тоже пустым видом, но во всю высоту поля: на новых
    // системах вертикаль от него не зависит, а на старых сюда не доходят.
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 44)];

    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
}

/**
 * Скруглённая плашка с градиентом — фон кнопки на iOS 6.
 *
 * Рисуется высотой чуть больше двух радиусов и растягивается по середине:
 * так одна картинка годится кнопке любой ширины и высоты, и её не надо
 * перерисовывать при повороте экрана.
 */
+ (UIImage *)glossImageWithColor:(UIColor *)color radius:(CGFloat)radius {
    return [self glossImageWithColor:color radius:radius sunken:NO];
}

+ (UIImage *)glossImageWithColor:(UIColor *)color
                          radius:(CGFloat)radius
                          sunken:(BOOL)sunken {
    CGFloat r = 0, g = 0, b = 0, a = 1;

    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        [color getWhite:&r alpha:&a];
        g = b = r;
    }

    CGFloat cap = MAX(radius, 1.0);
    CGSize size = CGSizeMake(cap * 2 + 1, cap * 2 + 1);

    UIGraphicsBeginImageContextWithOptions(size, NO, 0);

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect rect = CGRectMake(0.5, 0.5, size.width - 1, size.height - 1);

    /**
     * Сверху светлее, снизу темнее — так рисовали всё до iOS 7.
     *
     * Доли подобраны так, чтобы выпуклость читалась, а цвет оставался
     * узнаваемым: жёлтая кнопка должна остаться жёлтой, а не превратиться
     * в оранжевую с лимонной каймой.
     */
    CGFloat top[4]    = { MIN(1, r + (1 - r) * 0.30), MIN(1, g + (1 - g) * 0.30),
                          MIN(1, b + (1 - b) * 0.30), a };
    CGFloat middle[4] = { r, g, b, a };
    CGFloat bottom[4] = { r * 0.86, g * 0.86, b * 0.86, a };

    CGFloat components[12];

    memcpy(components,     top,    sizeof(top));
    memcpy(components + 4, middle, sizeof(middle));
    memcpy(components + 8, bottom, sizeof(bottom));

    // Блик занимает верхнюю половину, дальше ровный цвет с затемнением к низу.
    CGFloat locations[3] = { 0.0, 0.5, 1.0 };

    // У углубления свет падает так же, а поверхность вогнута: тень наверху,
    // отблеск внизу. Тот же градиент, перевёрнутый.
    if (sunken) {
        CGFloat swap[4];

        memcpy(swap, components, sizeof(swap));
        memcpy(components, components + 8, sizeof(swap));
        memcpy(components + 8, swap, sizeof(swap));
    }

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient =
        CGGradientCreateWithColorComponents(space, components, locations, 3);

    // Обрезка по скруглению — иначе градиент зальёт и углы.
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];

    CGContextSaveGState(context);
    [path addClip];

    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0),
                                CGPointMake(0, size.height), 0);

    CGContextRestoreGState(context);

    // Тёмная рамка по краю: без неё плашка сливается с фоном экрана.
    [[UIColor colorWithRed:r * 0.62 green:g * 0.62 blue:b * 0.62 alpha:a] setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return [image stretchableImageWithLeftCapWidth:(NSInteger)cap
                                      topCapHeight:(NSInteger)cap];
}

+ (void)decorateButton:(UIButton *)button color:(UIColor *)color radius:(CGFloat)radius {
    if (![self isLegacy]) {
        button.backgroundColor = color;
        button.layer.cornerRadius = radius;

        return;
    }

    CGFloat r = 0, g = 0, b = 0, a = 1;

    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        [color getWhite:&r alpha:&a];
        g = b = r;
    }

    /**
     * Прозрачный цвет — не плашка, а её отсутствие.
     *
     * Кнопки дней в полосе недели и в календаре так и переключаются:
     * выбранный день жёлтый, остальные прозрачные. Нарисовать плашку
     * из прозрачного цвета нельзя — вышел бы серый призрак, — поэтому
     * невыбранным картинки просто снимаются.
     */
    if (a < 0.02) {
        button.backgroundColor = [UIColor clearColor];

        [button setBackgroundImage:nil forState:UIControlStateNormal];
        [button setBackgroundImage:nil forState:UIControlStateHighlighted];

        return;
    }

    // Нажатая кнопка притемняется целиком — на iOS 6 подсветкой служил
    // не полупрозрачный слой поверх, а вторая, более тёмная картинка.
    UIColor *pressed = [UIColor colorWithRed:r * 0.82 green:g * 0.82 blue:b * 0.82 alpha:a];

    button.backgroundColor = [UIColor clearColor];
    button.layer.cornerRadius = 0.0;

    [button setBackgroundImage:[self glossImageWithColor:color radius:radius]
                      forState:UIControlStateNormal];

    [button setBackgroundImage:[self glossImageWithColor:pressed radius:radius]
                      forState:UIControlStateHighlighted];
}

static const NSInteger YCSkinTag = 0x7C5C;

+ (void)skin:(UIView *)view color:(UIColor *)color radius:(CGFloat)radius sunken:(BOOL)sunken {
    // Прежняя подложка снимается всегда: вид могли перекрасить. Карточки
    // в сетке дня именно так и живут — переиспользуются под другие записи.
    UIView *previous = [view viewWithTag:YCSkinTag];

    if (previous != nil && previous.superview == view) {
        [previous removeFromSuperview];
    }

    view.layer.cornerRadius = radius;

    if (![self isLegacy]) {
        view.backgroundColor = color;

        return;
    }

    CGFloat r = 0, g = 0, b = 0, a = 1;

    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        [color getWhite:&r alpha:&a];
        g = b = r;
    }

    // Прозрачное остаётся прозрачным: подложки из ничего не бывает.
    if (a < 0.02) {
        view.backgroundColor = [UIColor clearColor];

        return;
    }

    view.backgroundColor = [UIColor clearColor];

    UIColor *light = [UIColor colorWithRed:MIN(1, r + (1 - r) * 0.30)
                                     green:MIN(1, g + (1 - g) * 0.30)
                                      blue:MIN(1, b + (1 - b) * 0.30)
                                     alpha:a];

    UIColor *dark = [UIColor colorWithRed:r * 0.86 green:g * 0.86 blue:b * 0.86 alpha:a];

    YCSkinView *skin = [[YCSkinView alloc] initWithFrame:view.bounds];

    skin.tag = YCSkinTag;
    skin.userInteractionEnabled = NO;
    skin.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                            UIViewAutoresizingFlexibleHeight;

    CAGradientLayer *gradient = (CAGradientLayer *)skin.layer;

    /**
     * Выпуклое светлеет кверху, вогнутое — книзу.
     *
     * Свет в этом языке оформления всегда падает сверху: у приподнятой
     * поверхности блик наверху, у углубления там же лежит тень от края.
     */
    gradient.colors = sunken
        ? @[ (id)dark.CGColor, (id)color.CGColor, (id)light.CGColor ]
        : @[ (id)light.CGColor, (id)color.CGColor, (id)dark.CGColor ];

    gradient.locations = @[ @0.0, @0.5, @1.0 ];
    gradient.cornerRadius = radius;

    /**
     * Кайма — только у скруглённого.
     *
     * Скруглённое в этом языке оформления — предмет: карточка, кнопка,
     * плашка, и у предмета есть край. Прямоугольная полоса во всю ширину —
     * не предмет, а поверхность: шапка сетки, уголок над шкалой, полоса
     * времени в карточке. Каймой их обвести значит расчертить экран
     * коробками, а соседние полосы получили бы по своей линии на стыке —
     * шапка и уголок стоят вплотную, и вышел бы шов посередине.
     */
    if (radius > 0.5) {
        gradient.borderWidth = 1.0;
        gradient.borderColor = [UIColor colorWithRed:r * 0.62 green:g * 0.62
                                                blue:b * 0.62 alpha:a].CGColor;
    }

    [view insertSubview:skin atIndex:0];
}

+ (void)decoratePanel:(UIView *)view color:(UIColor *)color radius:(CGFloat)radius {
    [self skin:view color:color radius:radius sunken:NO];
}

+ (void)decorateWell:(UIView *)view color:(UIColor *)color radius:(CGFloat)radius {
    [self skin:view color:color radius:radius sunken:YES];
}

/**
 * Отдавать ли отрисовку списка системе.
 *
 * Да — только на iOS 6 и только в светлой теме: там системный вид ячеек
 * и есть тот скевоморфизм, которого мы добиваемся, и любой свой цвет фона
 * его портит. В тёмной теме и на новых системах красим сами.
 */
+ (BOOL)systemDrawsLists {
    return [self isLegacy] && ![self isDark];
}

+ (void)decorateCell:(UITableViewCell *)cell {
    if ([self systemDrawsLists]) {
        return;
    }

    cell.backgroundColor = [self background];
}

+ (void)decorateTable:(UITableView *)table color:(UIColor *)color {
    if ([self systemDrawsLists]) {
        return;
    }

    /**
     * У сгруппированного списка на iOS 6 цвет фона сам по себе не виден.
     *
     * Позади содержимого там лежит отдельный вид — backgroundView, — и это
     * он рисует ту светло-серую подложку с рамкой, к которой все привыкли.
     * Заданный цвет фона оказывается **под** ним и не проступает нигде:
     * в тёмной теме экран «О программе» выходил чёрными плашками на светло-
     * сером поле. Плашки чернели потому, что скругление ячейки iOS 6 рисует
     * как раз цветом фона ячейки, а вот поле вокруг них оставалось чужим.
     *
     * Убирается это только снятием самого вида. Через UIAppearance так
     * нельзя — оттого и делается здесь, каждому списку отдельно.
     *
     * В светлой теме до сюда не доходит: там системная подложка и есть
     * то, что нужно.
     */
    if ([self isLegacy]) {
        table.backgroundView = nil;
    }

    table.backgroundColor = color;
}

@end
