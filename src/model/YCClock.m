#import "YCClock.h"

#import <mach/mach_time.h>

// Тот же штамп, что и у YCExpiry: время сборки нужно здесь как нижняя
// граница здравого смысла — см. adoptTime:.
#if __has_include("YCBuildStamp.h")
#import "YCBuildStamp.h"
#endif

#ifndef YC_BUILD_EPOCH
#define YC_BUILD_EPOCH 0
#endif

/** Десять лет — потолок правдоподобия для ответа сервера. */
static const NSTimeInterval YCClockSaneSpan = 10 * 365 * 24 * 60 * 60;

/** Запомненное время сервера — переживает перезапуск. */
static NSString *const YCClockKey = @"clock.serverTime";

/** Точка отсчёта: время сервера и показание монотонного счётчика при нём. */
static NSTimeInterval YCClockBase;
static uint64_t YCClockBaseTicks;
static BOOL YCClockKnown;

/**
 * Секунды, прошедшие с указанного показания монотонного счётчика.
 *
 * mach_absolute_time идёт в «тиках», и их длительность зависит от машины:
 * на armv7 множитель не единица. Пересчёт берётся из системы один раз —
 * он неизменен, пока устройство включено.
 *
 * Счётчик не зависит от часов совсем: перевод времени в настройках его
 * не двигает. Обнуляется он только при перезагрузке, а точку отсчёта мы
 * после каждого ответа сервера ставим заново.
 */
static NSTimeInterval YCClockSecondsSince(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ mach_timebase_info(&timebase); });

    uint64_t now = mach_absolute_time();

    if (timebase.denom == 0 || now <= ticks) {
        return 0;
    }

    return (NSTimeInterval)(now - ticks) *
           timebase.numer / timebase.denom / NSEC_PER_SEC;
}

@implementation YCClock

/**
 * Разборщик даты HTTP.
 *
 * Локаль обязательно en_US_POSIX: под русской локалью «Mon» и «Sep»
 * не разбираются вовсе, и заголовок молча превращался бы в nil.
 * Пояс задан явно — в RFC 1123 время всегда по Гринвичу.
 */
+ (NSDateFormatter *)parser {
    static NSDateFormatter *parser;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        parser = [[NSDateFormatter alloc] init];

        parser.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        parser.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        parser.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
    });

    return parser;
}

/** Ставит точку отсчёта, если новое время позже уже известного. */
+ (void)adoptTime:(NSTimeInterval)time persist:(BOOL)persist {
    if (time <= 0) {
        return;
    }

    /**
     * Заведомая чушь отвергается — иначе одна такая отметка калечит сборку
     * навсегда.
     *
     * Показания только растут и переживают перезапуск, а значит один ответ
     * с датой в 2035 году запер бы приложение намертво: переустановка
     * не помогает, настройки живут в папке пользователя, а не в связке.
     *
     * Нижняя граница — время сборки, и она безупречна логически: ответ,
     * который видит этот двоичный файл, не может быть старше самого файла.
     * Отсекает и переведённые назад часы промежуточного узла, и мусор
     * от неудачного разбора.
     *
     * Верхняя — десять лет от сборки. Число взято с запасом нарочно: срок
     * жизни сборки неделя, и всё, что дальше, для проверки «уже истёк»
     * одинаково истекло. Отвергать надо не «поздно», а «невозможно».
     */
    if (YC_BUILD_EPOCH > 0) {
        NSTimeInterval built = (NSTimeInterval)YC_BUILD_EPOCH;

        if (time < built || time > built + YCClockSaneSpan) {
            return;
        }
    }

    @synchronized (self) {
        if (YCClockKnown && time <= YCClockBase) {
            return;
        }

        YCClockBase = time;
        YCClockBaseTicks = mach_absolute_time();
        YCClockKnown = YES;
    }

    if (persist) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        [defaults setDouble:time forKey:YCClockKey];
        [defaults synchronize];
    }
}

/**
 * Поднимает запомненное время при первом обращении.
 *
 * После перезапуска монотонный счётчик начинается заново, и досчитывать
 * от запомненной точки можно только время текущего запуска. Это по-прежнему
 * нижняя оценка — ровно то, что нужно.
 */
+ (void)loadIfNeeded {
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        NSTimeInterval saved =
            [[NSUserDefaults standardUserDefaults] doubleForKey:YCClockKey];

        [self adoptTime:saved persist:NO];
    });
}

+ (void)noteServerDate:(NSString *)httpDate {
    if ([httpDate length] == 0) {
        return;
    }

    [self loadIfNeeded];

    NSDate *date = nil;

    @synchronized ([self parser]) {
        date = [[self parser] dateFromString:httpDate];
    }

    if (date == nil) {
        return;
    }

    [self adoptTime:[date timeIntervalSince1970] persist:YES];
}

+ (BOOL)isVerified {
    [self loadIfNeeded];

    @synchronized (self) {
        return YCClockKnown;
    }
}

+ (NSDate *)now {
    [self loadIfNeeded];

    NSTimeInterval base;
    uint64_t ticks;

    @synchronized (self) {
        if (!YCClockKnown) {
            return nil;
        }

        base = YCClockBase;
        ticks = YCClockBaseTicks;
    }

    return [NSDate dateWithTimeIntervalSince1970:base + YCClockSecondsSince(ticks)];
}

@end
