#import "YCExpiry.h"

#import "YCClock.h"

/**
 * Время сборки в секундах от 1970 года.
 *
 * Заголовок пишет Makefile при каждой сборке. Если его нет — значит собрано
 * в обход makefile (скажем, разбором на лету в редакторе), и срока у такой
 * сборки нет вовсе. Ставить срок от нулевого времени было бы хуже всего:
 * неделя от 1970 года истекла давно, и приложение отказывалось бы работать
 * с первого же запуска.
 */
#if __has_include("YCBuildStamp.h")
#import "YCBuildStamp.h"
#endif

#ifndef YC_BUILD_EPOCH
#define YC_BUILD_EPOCH 0
#endif

/** Неделя. */
static const NSTimeInterval YCExpiryLifetime = 7 * 24 * 60 * 60;

@implementation YCExpiry

+ (NSDate *)buildDate {
    return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)YC_BUILD_EPOCH];
}

+ (NSDate *)deadline {
    return [[self buildDate] dateByAddingTimeInterval:YCExpiryLifetime];
}

/** Есть ли у сборки срок вообще. */
+ (BOOL)isLimited {
    return YC_BUILD_EPOCH > 0;
}

+ (BOOL)isExpired {
    if (![self isLimited]) {
        return NO;
    }

    NSDate *now = [YCClock now];

    if (now == nil) {
        return NO;
    }

    return [now compare:[self deadline]] == NSOrderedDescending;
}

/** «8 сентября» — коротко, без года и времени. */
+ (NSString *)shortDate:(NSDate *)date {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];

        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
        formatter.dateFormat = @"d MMMM";
    });

    return [formatter stringFromDate:date];
}

+ (NSString *)notice {
    if (![self isLimited]) {
        return nil;
    }

    NSString *built = [self shortDate:[self buildDate]];
    NSString *until = [self shortDate:[self deadline]];

    if ([self isExpired]) {
        return [NSString stringWithFormat:
                @"Срок этой сборки истёк %@. Она больше не работает — "
                @"нужна свежая.", until];
    }

    if (![YCClock isVerified]) {
        /**
         * Пока сервер не ответил, срок ещё не проверен — так и сказано.
         *
         * Подставить сюда часы устройства было бы проще и честнее не было бы:
         * человек прочёл бы «работает до 15-го», а на деле это значит лишь
         * «в устройстве стоит такое число».
         */
        return [NSString stringWithFormat:
                @"Сборка от %@, работает неделю — до %@. "
                @"Срок сверяется с часами сервера при первом запросе.",
                built, until];
    }

    return [NSString stringWithFormat:@"Сборка от %@, работает до %@.", built, until];
}

@end
