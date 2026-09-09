#import "YCProxy.h"

#import "YCHttp.h"

static NSString *const YCProxyEnabledKey = @"proxy_enabled";
static NSString *const YCProxyHostKey = @"proxy_host";
static NSString *const YCProxyPortKey = @"proxy_port";

/**
 * Значения по умолчанию — те, что были названы при постановке задачи.
 *
 * Вписаны сюда, а не оставлены пустыми, ровно затем, чтобы включение прокси
 * было одним движением переключателя: адрес перехватчика в отладочной сети
 * не меняется от сеанса к сеансу, и набирать его на экранной клавиатуре
 * каждый раз — работа, которой можно не быть.
 */
static NSString *const YCProxyDefaultHost = @"192.168.1.183";
static const NSInteger YCProxyDefaultPort = 8886;

@implementation YCProxy

+ (BOOL)isCompiledIn {
#ifdef YC_PROXY
    return YES;
#else
    return NO;
#endif
}

#ifndef YC_PROXY

/**
 * Готовая сборка: прокси здесь нет, и это не фигура речи.
 *
 * Ниже — заглушки, и всё остальное выброшено разборщиком. В двоичном
 * файле не остаётся ни адреса по умолчанию, ни ключей в настройках,
 * ни экрана с переключателем: переключать нечего, потому что нечему.
 *
 * Так и задумано. Включённый прокси снимает проверку сертификата —
 * иначе перехватчик не заработает, он подменяет сертификат своим, — то есть
 * открывает соединение тому, кто стоит посередине. А через это соединение
 * идут логин и пароль от YClients. В сборке для отладки это средство,
 * в сборке для людей — оружие против них же.
 */
+ (void)dropConnections {}
+ (BOOL)isSupported { return NO; }
+ (BOOL)isEnabled { return NO; }
+ (void)setEnabled:(BOOL)enabled {}
+ (NSString *)host { return @""; }
+ (void)setHost:(NSString *)host {}
+ (NSInteger)port { return 0; }
+ (void)setPort:(NSInteger)port {}
+ (BOOL)isActive { return NO; }
+ (NSString *)address { return @""; }
+ (NSString *)summary { return nil; }

@end

#else

/** Соединения закрываются при любой правке: иначе запросы пойдут по старым. */
+ (void)dropConnections {
    [YCHttp dropPooledConnections];
}

+ (BOOL)isSupported {
    /**
     * Теперь всегда.
     *
     * Прежняя реализация стояла на NSURLSession и требовала iOS 7 — то есть
     * на iPad 2, где отладка нужнее всего, прокси был недоступен. С переходом
     * на свой TLS туннель CONNECT пробивается своими силами (см. YCTls.h),
     * и версия системы к делу больше не относится.
     */
    return YES;
}

#pragma mark Значения

+ (BOOL)isEnabled {
    if (![self isCompiledIn]) {
        return NO;
    }

    return [[NSUserDefaults standardUserDefaults] boolForKey:YCProxyEnabledKey];
}

+ (void)setEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setBool:enabled forKey:YCProxyEnabledKey];
    [defaults synchronize];

    [self dropConnections];

    NSLog(@"[YClients/Прокси] %@ (%@)",
          enabled ? @"включён" : @"выключен", [self address]);
}

+ (NSString *)host {
    NSString *host = [[NSUserDefaults standardUserDefaults] stringForKey:YCProxyHostKey];

    // Пустая строка в настройках значит то же, что и отсутствие ключа:
    // поле адреса очистили, но значение по умолчанию никуда не делось.
    return [host length] > 0 ? host : YCProxyDefaultHost;
}

+ (void)setHost:(NSString *)host {
    NSString *trimmed = [host stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setObject:(trimmed ?: @"") forKey:YCProxyHostKey];
    [defaults synchronize];

    [self dropConnections];
}

+ (NSInteger)port {
    NSInteger port = [[NSUserDefaults standardUserDefaults] integerForKey:YCProxyPortKey];

    // Ноль — это и «не задано», и «набрали ерунду»: порта 0 не бывает,
    // а отличать одно от другого здесь незачем.
    return (port > 0 && port < 65536) ? port : YCProxyDefaultPort;
}

+ (void)setPort:(NSInteger)port {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setInteger:port forKey:YCProxyPortKey];
    [defaults synchronize];

    [self dropConnections];
}

#pragma mark Состояние

+ (BOOL)isActive {
    return [self isCompiledIn] && [self isSupported] &&
           [self isEnabled] && [[self host] length] > 0;
}

+ (NSString *)address {
    return [NSString stringWithFormat:@"%@:%ld", [self host], (long)[self port]];
}

+ (NSString *)summary {
    if (![self isEnabled]) {
        return @"выключен";
    }

    if (![self isSupported]) {
        // Включён, но работать не будет. Сказать об этом надо здесь:
        // иначе «включено, а трафика в перехватчике нет» пришлось бы
        // разгадывать по журналу.
        return @"нужна iOS 7";
    }

    return [self address];
}

@end

#endif  /* YC_PROXY */
