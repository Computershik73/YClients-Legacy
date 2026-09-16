#import "YCTime.h"

/**
 * Единственный пояс приложения.
 *
 * GMT здесь означает не «время по Гринвичу», а «пояс без перевода часов
 * и без настроек пользователя». Всё, что мы кладём в NSDate, — это
 * настенные часы филиала; GMT нужен только затем, чтобы они не поехали.
 */
static NSTimeZone *YCZone(void) {
    static NSTimeZone *zone;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ zone = [NSTimeZone timeZoneForSecondsFromGMT:0]; });

    return zone;
}

NSCalendar *YCCalendar(void) {
    static NSCalendar *calendar;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        // Григорианский задан явно: под персидским или буддийским календарём
        // «прибавить сутки» даёт другой результат, а пользователь календаря
        // системы для этого не выбирал.
        calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        calendar.timeZone = YCZone();
        calendar.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];

        // Неделя с понедельника — так её видит и веб-интерфейс YClients.
        calendar.firstWeekday = 2;
    });

    return calendar;
}

/**
 * Форматтер с фиксированной локалью.
 *
 * en_US_POSIX обязателен для разбора: под другой локалью пользователь
 * может выбрать 12-часовые часы в настройках, и тогда `HH` при **разборе**
 * ведёт себя не так, как ожидает шаблон. Это давняя ловушка, и она не
 * теоретическая — на 12-часовом устройстве разбор просто отдаёт nil.
 */
static NSDateFormatter *YCFormatter(NSString *format) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    // Форматтер стоит недёшево, а зовутся они на каждую запись при отрисовке
    // сетки. Замок — потому что YCApi разбирает даты со своей очереди,
    // а интерфейс форматирует их с главного потока.
    @synchronized (cache) {
        NSDateFormatter *formatter = [cache objectForKey:format];

        if (formatter == nil) {
            formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = YCZone();
            formatter.dateFormat = format;

            [cache setObject:formatter forKey:format];
        }

        return formatter;
    }
}

NSDate *YCDateFromAPI(NSString *string) {
    if ([string length] < 10) {
        return nil;
    }

    /**
     * Пояс отбрасывается обрезкой, а не разбором.
     *
     * Строка приходит в двух видах — `2026-09-04T12:00:00+03:00` и
     * `2026-09-04 12:00:00`, — и в первом хвост после секунд нам не нужен
     * (см. YCTime.h). Брать первые 19 знаков надёжнее, чем перечислять
     * шаблоны со смещением: их у ISO 8601 три вида (`+03:00`, `+0300`, `Z`),
     * и промах по любому из них дал бы nil вместо времени.
     */
    NSString *head = [string length] > 19 ? [string substringToIndex:19] : string;

    // Разделитель между датой и временем у сервера непостоянен.
    head = [head stringByReplacingOccurrencesOfString:@"T" withString:@" "];

    NSDate *date = [YCFormatter(@"yyyy-MM-dd HH:mm:ss") dateFromString:head];

    if (date != nil) {
        return date;
    }

    // Поле `date` у некоторых ответов приходит одним днём, без времени.
    return [YCFormatter(@"yyyy-MM-dd") dateFromString:
                [head length] > 10 ? [head substringToIndex:10] : head];
}

NSString *YCAPIFromDate(NSDate *date) {
    return [YCFormatter(@"yyyy-MM-dd HH:mm:ss") stringFromDate:date];
}

NSString *YCDayFromDate(NSDate *date) {
    return [YCFormatter(@"yyyy-MM-dd") stringFromDate:date];
}

NSString *YCClockFromDate(NSDate *date) {
    return [YCFormatter(@"HH:mm") stringFromDate:date];
}

NSString *YCTitleFromDate(NSDate *date) {
    // Заголовок читает человек, поэтому здесь локаль русская, а не POSIX:
    // нужны названия месяцев и дней недели. Пояс всё тот же.
    static NSDateFormatter *formatter;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
        formatter.timeZone = YCZone();

        // `d MMMM` даёт родительный падеж («4 сентября»), а не именительный,
        // — в отличие от `MMMM`, которое дало бы «Сентябрь».
        formatter.dateFormat = @"EEEEEE, d MMMM";
    });

    NSString *title = nil;

    @synchronized (formatter) {
        title = [formatter stringFromDate:date];
    }

    return title;
}

/** Форматтер с русскими названиями — для заголовков, которые читает человек. */
static NSString *YCRussian(NSString *format, NSDate *date) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    @synchronized (cache) {
        NSDateFormatter *formatter = [cache objectForKey:format];

        if (formatter == nil) {
            formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
            formatter.timeZone = YCZone();
            formatter.dateFormat = format;

            [cache setObject:formatter forKey:format];
        }

        return [formatter stringFromDate:date];
    }
}

NSString *YCShortTitleFromDate(NSDate *date) {
    return YCRussian(@"d MMMM", date);
}

NSString *YCLongTitleFromDate(NSDate *date) {
    return YCRussian(@"d MMMM yyyy", date);
}

NSString *YCMonthTitleFromDate(NSDate *date) {
    // LLLL — именительный падеж («Сентябрь»), в отличие от MMMM.
    NSString *month = YCRussian(@"LLLL", date);

    return [month length] > 0
        ? [[[month substringToIndex:1] uppercaseString]
              stringByAppendingString:[month substringFromIndex:1]]
        : month;
}

NSString *YCDateTimeFromDate(NSDate *date) {
    return YCRussian(@"d MMMM yyyy, HH:mm", date);
}

NSDate *YCStartOfDay(NSDate *date) {
    NSCalendar *calendar = YCCalendar();

    NSDateComponents *parts = [calendar components:(NSYearCalendarUnit |
                                                    NSMonthCalendarUnit |
                                                    NSDayCalendarUnit)
                                          fromDate:date];

    return [calendar dateFromComponents:parts];
}

NSDate *YCDayByAdding(NSDate *date, NSInteger days) {
    NSDateComponents *shift = [[NSDateComponents alloc] init];

    shift.day = days;

    // Через календарь, а не прибавлением 86400 секунд: в GMT перевода часов
    // нет и разницы быть не должно, но правило «арифметика дат — календарём»
    // стоит держать даже там, где сегодня можно и без него.
    return [YCCalendar() dateByAddingComponents:shift
                                         toDate:YCStartOfDay(date)
                                        options:0];
}

NSTimeInterval YCSecondsIntoDay(NSDate *date) {
    return [date timeIntervalSinceDate:YCStartOfDay(date)];
}

NSDate *YCDateWithSecondsIntoDay(NSDate *day, NSTimeInterval seconds) {
    return [YCStartOfDay(day) dateByAddingTimeInterval:seconds];
}

BOOL YCSameDay(NSDate *a, NSDate *b) {
    if (a == nil || b == nil) {
        return NO;
    }

    return [YCStartOfDay(a) isEqualToDate:YCStartOfDay(b)];
}
