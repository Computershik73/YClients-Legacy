#import "YCHttp.h"

#import "YCProxy.h"
#import "YCTls.h"

static NSString *const YCHttpErrorDomain = @"ru.computershik.yclients.http";

static const NSTimeInterval YCHttpTimeout = 30.0;
static const NSUInteger YCHttpMaxRedirects = 5;
static const NSUInteger YCHttpMaxBody = 8 * 1024 * 1024;

/**
 * Сколько соединение ждёт следующего запроса, прежде чем его закрыть.
 * Больше держать бессмысленно: сервер закрывает раньше нас, и мы получаем
 * только лишнюю попытку с повтором.
 */
static const NSTimeInterval YCHttpKeepAlive = 20.0;

static NSError *YCHttpMakeError(NSInteger code, NSString *text) {
    return [NSError errorWithDomain:YCHttpErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: text }];
}

@implementation YCHttpResponse
@end


#pragma mark - Класс по имени

Class YCNetworkClass(NSString *name) {
    /**
     * Осталось от прежней реализации на NSURLConnection и нужно до сих пор.
     *
     * Сам транспорт классов NSURL больше не трогает — но NSMutableURLRequest
     * и NSHTTPURLResponse ходят по приложению как обычные объекты-переносчики,
     * а компоновщик, собирая против SDK 9.3, записал бы им источником
     * CFNetwork. На iOS 6 и 7 эти классы лежат в Foundation, и приложение
     * не запустилось бы вовсе — отказом загрузчика, до main и без записи
     * в журнале. Поиск по имени снимает и символ, и привязку к библиотеке.
     */
    return NSClassFromString(name);
}

NSMutableURLRequest *YCRequest(NSString *url, NSString *method, NSTimeInterval timeout) {
    NSURL *address = [NSURL URLWithString:url];

    if (address == nil) {
        NSLog(@"[YClients/HTTP] Адрес не разобран: %@", url);
        return nil;
    }

    NSMutableURLRequest *request =
        [YCNetworkClass(@"NSMutableURLRequest") requestWithURL:address
                                                  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                              timeoutInterval:timeout];

    [request setHTTPMethod:method];

    return request;
}


#pragma mark - Пул соединений

/**
 * Живые соединения между запросами.
 *
 * Каждое рукопожатие — это пара оборотов до сервера и проверка цепочки,
 * то есть сотни миллисекунд на планшете 2011 года. День календаря — это
 * три запроса подряд (сотрудники, записи, услуги); с пулом за них платится
 * одно рукопожатие вместо трёх.
 *
 * Соединение возвращается в пул, только если ответ дочитан до конца
 * и обе стороны согласны продолжать: иначе в трубе остаётся хвост чужого
 * ответа, и следующий запрос прочитает мусор вместо заголовков.
 */
@interface YCHttpIdleConnection : NSObject
@property (nonatomic, strong) YCTls *tls;
@property (nonatomic, strong) NSDate *since;
@end

@implementation YCHttpIdleConnection
@end

static NSMutableDictionary *YCHttpPool(void) {
    static NSMutableDictionary *pool = nil;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ pool = [NSMutableDictionary dictionary]; });

    return pool;
}

static NSLock *YCHttpPoolLock(void) {
    static NSLock *lock = nil;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ lock = [[NSLock alloc] init]; });

    return lock;
}

static YCTls *YCHttpTakeConnection(NSString *key) {
    NSLock *lock = YCHttpPoolLock();

    [lock lock];

    NSMutableArray *waiting = [YCHttpPool() objectForKey:key];
    YCTls *found = nil;

    while ([waiting count] > 0) {
        YCHttpIdleConnection *idle = [waiting lastObject];

        [waiting removeLastObject];

        // Просроченные закрываем, не пытаясь использовать: сервер их
        // наверняка уже закрыл со своей стороны.
        if (-[idle.since timeIntervalSinceNow] > YCHttpKeepAlive) {
            [idle.tls close];
            continue;
        }

        found = idle.tls;
        break;
    }

    [lock unlock];

    return found;
}

static void YCHttpReturnConnection(NSString *key, YCTls *tls) {
    YCHttpIdleConnection *idle = [[YCHttpIdleConnection alloc] init];

    idle.tls = tls;
    idle.since = [NSDate date];

    NSLock *lock = YCHttpPoolLock();

    [lock lock];

    NSMutableArray *waiting = [YCHttpPool() objectForKey:key];

    if (waiting == nil) {
        waiting = [NSMutableArray array];
        [YCHttpPool() setObject:waiting forKey:key];
    }

    // Больше двух на узел не держим: запросы идут по одному, с очереди YCApi.
    if ([waiting count] >= 2) {
        [[(YCHttpIdleConnection *)[waiting objectAtIndex:0] tls] close];
        [waiting removeObjectAtIndex:0];
    }

    [waiting addObject:idle];
    [lock unlock];
}

/** Все соединения закрыть — при смене настроек прокси. */
static void YCHttpDropPool(void) {
    NSLock *lock = YCHttpPoolLock();

    [lock lock];

    for (NSArray *waiting in [YCHttpPool() allValues]) {
        for (YCHttpIdleConnection *idle in waiting) {
            [idle.tls close];
        }
    }

    [YCHttpPool() removeAllObjects];
    [lock unlock];
}


#pragma mark - Чтение ответа

/**
 * Заголовки: читаем, пока не встретится пустая строка. Всё, что прочлось
 * после неё, — уже начало тела, и его надо не потерять.
 */
static NSString *YCHttpReadHead(YCTls *tls, NSMutableData *tail, NSError **error) {
    NSMutableData *head = [NSMutableData data];
    uint8_t buffer[4096];

    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];

    while (1) {
        NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:error];

        if (got == YCTlsReadTimedOut) {
            continue;
        }

        if (got < 0) {
            return nil;
        }

        if (got == 0) {
            if (error) {
                *error = YCHttpMakeError(2, @"соединение закрыто до заголовков");
            }

            return nil;
        }

        [head appendBytes:buffer length:(NSUInteger)got];

        NSRange border = [head rangeOfData:separator
                                   options:0
                                     range:NSMakeRange(0, [head length])];

        if (border.location != NSNotFound) {
            NSUInteger bodyStart = border.location + border.length;

            [tail appendData:[head subdataWithRange:
                NSMakeRange(bodyStart, [head length] - bodyStart)]];

            NSData *headOnly = [head subdataWithRange:NSMakeRange(0, border.location)];

            return [[NSString alloc] initWithData:headOnly encoding:NSISOLatin1StringEncoding];
        }

        if ([head length] > 128 * 1024) {
            if (error) {
                *error = YCHttpMakeError(2, @"заголовки без конца");
            }

            return nil;
        }
    }
}

/** Тело, длина которого объявлена заранее. */
static NSData *YCHttpReadFixed(YCTls *tls, NSMutableData *already,
                               NSUInteger length, NSError **error) {
    NSMutableData *body = [already mutableCopy];
    uint8_t buffer[16384];

    while ([body length] < length) {
        NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:error];

        if (got == YCTlsReadTimedOut) {
            continue;
        }

        if (got < 0) {
            return nil;
        }

        if (got == 0) {
            break;      // сервер закрыл раньше обещанного — отдаём что есть
        }

        [body appendBytes:buffer length:(NSUInteger)got];

        if ([body length] > YCHttpMaxBody) {
            if (error) {
                *error = YCHttpMakeError(2, @"ответ длиннее разумного");
            }

            return nil;
        }
    }

    return body;
}

/**
 * Тело «кусками»: перед каждым куском идёт его длина шестнадцатеричным
 * числом, нулевая длина означает конец. Так отвечают, когда размер заранее
 * неизвестен, — и именно так приходят списки записей.
 */
static NSData *YCHttpReadChunked(YCTls *tls, NSMutableData *already, NSError **error) {
    NSMutableData *buffered = [already mutableCopy];
    NSMutableData *body = [NSMutableData data];
    uint8_t buffer[16384];

    NSData *crlf = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];

    while (1) {
        NSRange lineEnd = [buffered rangeOfData:crlf options:0
                                          range:NSMakeRange(0, [buffered length])];

        while (lineEnd.location == NSNotFound) {
            NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:error];

            if (got == YCTlsReadTimedOut) {
                continue;
            }

            if (got < 0) {
                return nil;
            }

            if (got == 0) {
                return body;    // оборвалось — отдаём собранное
            }

            [buffered appendBytes:buffer length:(NSUInteger)got];
            lineEnd = [buffered rangeOfData:crlf options:0
                                      range:NSMakeRange(0, [buffered length])];
        }

        NSString *sizeLine = [[NSString alloc]
            initWithData:[buffered subdataWithRange:NSMakeRange(0, lineEnd.location)]
                encoding:NSASCIIStringEncoding];

        // После длины через точку с запятой могут идти «расширения» —
        // их никто не использует, но отрезать надо.
        NSRange semicolon = [sizeLine rangeOfString:@";"];

        if (semicolon.location != NSNotFound) {
            sizeLine = [sizeLine substringToIndex:semicolon.location];
        }

        unsigned int chunkSize = 0;

        if ([sizeLine length] == 0 ||
            ![[NSScanner scannerWithString:sizeLine] scanHexInt:&chunkSize]) {
            if (error) {
                *error = YCHttpMakeError(2, @"нечитаемая длина куска");
            }

            return nil;
        }

        [buffered replaceBytesInRange:NSMakeRange(0, lineEnd.location + lineEnd.length)
                            withBytes:NULL length:0];

        if (chunkSize == 0) {
            return body;    // последний кусок
        }

        NSUInteger need = (NSUInteger)chunkSize + 2;   // кусок плюс завершающий CRLF

        while ([buffered length] < need) {
            NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:error];

            if (got == YCTlsReadTimedOut) {
                continue;
            }

            if (got < 0) {
                return nil;
            }

            if (got == 0) {
                return body;
            }

            [buffered appendBytes:buffer length:(NSUInteger)got];
        }

        [body appendData:[buffered subdataWithRange:NSMakeRange(0, chunkSize)]];
        [buffered replaceBytesInRange:NSMakeRange(0, need) withBytes:NULL length:0];

        if ([body length] > YCHttpMaxBody) {
            if (error) {
                *error = YCHttpMakeError(2, @"ответ длиннее разумного");
            }

            return nil;
        }
    }
}


#pragma mark - Запрос

@implementation YCHttp

/**
 * Один заход: взять соединение (из пула или новое), отправить, прочитать.
 *
 * `reused` говорит вызывающему, было ли соединение из пула. Это важно для
 * повтора: соединение из пула могло быть закрыто сервером, пока лежало
 * без дела, и обрыв на первом же чтении — не отказ сети, а обычное дело.
 * Новое же соединение, оборвавшееся сразу, — настоящий отказ.
 */
+ (YCHttpResponse *)attempt:(NSURLRequest *)request
                  redirects:(NSUInteger)redirects
                     reused:(BOOL *)reused {
    YCHttpResponse *result = [[YCHttpResponse alloc] init];

    if (redirects > YCHttpMaxRedirects) {
        result.error = YCHttpMakeError(3, @"слишком много переадресаций");
        return result;
    }

    NSURL *url = [request URL];

    if ([[url host] length] == 0) {
        result.error = YCHttpMakeError(1, @"нечитаемый адрес");
        return result;
    }

    if (![[[url scheme] lowercaseString] isEqualToString:@"https"]) {
        // Незашифрованных запросов приложение не делает вовсе: единственное,
        // ради чего писался свой транспорт, — контроль над TLS, и дыра
        // в виде http:// обесценила бы всё остальное.
        result.error = YCHttpMakeError(1, @"поддерживается только https");
        return result;
    }

    uint16_t port = [url port] != nil ? (uint16_t)[[url port] intValue] : 443;

    NSString *path = [[url path] length] > 0 ? [url path] : @"/";

    if ([[url query] length] > 0) {
        path = [path stringByAppendingFormat:@"?%@", [url query]];
    }

    BOOL throughProxy = [YCProxy isActive];

    /**
     * Ключ пула включает прокси: соединения «напрямую» и «через
     * перехватчик» — разные трубы, и путать их нельзя. Стоит переключить
     * тумблер, как ключ меняется, и старые соединения просто не находятся.
     */
    NSString *poolKey = throughProxy
        ? [NSString stringWithFormat:@"%@:%u@%@", [url host], (unsigned)port, [YCProxy address]]
        : [NSString stringWithFormat:@"%@:%u", [url host], (unsigned)port];

    YCTls *tls = YCHttpTakeConnection(poolKey);

    if (reused != NULL) {
        *reused = (tls != nil);
    }

    if (tls == nil) {
        tls = [[YCTls alloc] initWithHost:[url host] port:port];

        if (throughProxy) {
            tls.proxyHost = [YCProxy host];
            tls.proxyPort = (uint16_t)[YCProxy port];

            // Перехватчик подменяет сертификат своим — честная проверка
            // его отвергнет, в этом и смысл отладочного режима.
            tls.insecure = YES;

            NSLog(@"[YClients/HTTP] Через прокси %@", [YCProxy address]);
        }

        NSError *connectError = nil;

        if (![tls connectWithTimeout:YCHttpTimeout error:&connectError]) {
            result.error = connectError;
            return result;
        }
    }

    // --- запрос ---

    NSString *method = [[request HTTPMethod] length] > 0 ? [request HTTPMethod] : @"GET";
    NSData *body = [request HTTPBody];

    NSMutableString *head =
        [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\n", method, path];

    [head appendFormat:@"Host: %@\r\n", [url host]];

    NSDictionary *headers = [request allHTTPHeaderFields];
    BOOL hasUserAgent = NO;

    for (NSString *key in headers) {
        if ([[key lowercaseString] isEqualToString:@"host"]) {
            continue;
        }

        if ([[key lowercaseString] isEqualToString:@"user-agent"]) {
            hasUserAgent = YES;
        }

        [head appendFormat:@"%@: %@\r\n", key, [headers objectForKey:key]];
    }

    if (!hasUserAgent) {
        [head appendString:@"User-Agent: YClients-iOS/1.0\r\n"];
    }

    // Сжатие не просим: распаковывать пришлось бы самим, а ответы здесь
    // невелики — день записей это десятки килобайт.
    [head appendString:@"Accept-Encoding: identity\r\n"];
    [head appendString:@"Connection: keep-alive\r\n"];

    if ([body length] > 0) {
        [head appendFormat:@"Content-Length: %lu\r\n", (unsigned long)[body length]];
    }

    [head appendString:@"\r\n"];

    NSData *headData = [head dataUsingEncoding:NSUTF8StringEncoding];
    NSError *writeError = nil;

    if ([tls writeBytes:[headData bytes] length:[headData length] error:&writeError] < 0) {
        [tls close];
        result.error = writeError;
        return result;
    }

    if ([body length] > 0 &&
        [tls writeBytes:[body bytes] length:[body length] error:&writeError] < 0) {
        [tls close];
        result.error = writeError;
        return result;
    }

    // --- ответ ---

    NSMutableData *tail = [NSMutableData data];
    NSError *readError = nil;
    NSString *rawHead = YCHttpReadHead(tls, tail, &readError);

    if (rawHead == nil) {
        [tls close];
        result.error = readError ?: YCHttpMakeError(2, @"пустой ответ");
        return result;
    }

    NSArray *lines = [rawHead componentsSeparatedByString:@"\r\n"];
    NSArray *statusParts = [lines count] > 0
        ? [[lines objectAtIndex:0] componentsSeparatedByString:@" "] : nil;

    if ([statusParts count] < 2) {
        [tls close];
        result.error = YCHttpMakeError(2, @"нечитаемая строка состояния");
        return result;
    }

    NSInteger status = [[statusParts objectAtIndex:1] integerValue];

    NSMutableDictionary *responseHeaders = [NSMutableDictionary dictionary];

    for (NSUInteger i = 1; i < [lines count]; i++) {
        NSString *line = [lines objectAtIndex:i];
        NSRange colon = [line rangeOfString:@":"];

        if (colon.location == NSNotFound) {
            continue;
        }

        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        [responseHeaders setObject:value forKey:name];
    }


    // --- переадресация ---

    NSString *location = [responseHeaders objectForKey:@"location"];

    if ((status == 301 || status == 302 || status == 303 || status == 307 || status == 308)
        && location != nil) {
        NSURL *next = [NSURL URLWithString:location relativeToURL:url];

        [tls close];

        if (next == nil) {
            result.error = YCHttpMakeError(1, @"нечитаемый адрес переадресации");
            return result;
        }

        NSMutableURLRequest *followed = [request mutableCopy];

        [followed setURL:next];

        // 302 и 303 на практике означают «дальше GET», даже если пришли
        // в ответ на POST: так делают все браузеры.
        if (status == 303 || status == 302) {
            [followed setHTTPMethod:@"GET"];
            [followed setHTTPBody:nil];
        }

        return [self attempt:followed redirects:redirects + 1 reused:NULL];
    }

    // --- тело ---

    NSData *data = nil;
    BOOL lengthKnown = YES;
    NSString *encoding = [[responseHeaders objectForKey:@"transfer-encoding"] lowercaseString];
    NSString *contentLength = [responseHeaders objectForKey:@"content-length"];

    /**
     * Проверка на nil обязательна, и это не перестраховка: сообщение
     * к nil возвращает нулевой NSRange, у которого location == 0, а ноль —
     * это не NSNotFound. Без явной проверки ответ без Transfer-Encoding
     * читался бы как «кусками», и первые же байты тела принимались бы
     * за длину куска.
     */
    if (encoding != nil && [encoding rangeOfString:@"chunked"].location != NSNotFound) {
        data = YCHttpReadChunked(tls, tail, &readError);
    } else if (contentLength != nil) {
        data = YCHttpReadFixed(tls, tail, (NSUInteger)[contentLength longLongValue], &readError);
    } else {
        // Ни длины, ни кусков: конец тела виден только по закрытию
        // соединения, поэтому и оставить его себе нельзя.
        lengthKnown = NO;
        data = YCHttpReadFixed(tls, tail, NSUIntegerMax, &readError);
    }

    if (data == nil) {
        [tls close];
        result.error = readError ?: YCHttpMakeError(2, @"тело не прочиталось");
        return result;
    }

    // Соединение возвращается в пул, только если ответ дочитан ровно
    // до конца и сервер не попрощался. Та же ловушка с nil: без проверки
    // отсутствующий заголовок читался бы как «сервер закрывает».
    NSString *connectionHeader = [[responseHeaders objectForKey:@"connection"] lowercaseString];
    BOOL serverClosing = connectionHeader != nil
        && [connectionHeader rangeOfString:@"close"].location != NSNotFound;

    if (lengthKnown && !serverClosing) {
        YCHttpReturnConnection(poolKey, tls);
    } else {
        [tls close];
    }

    result.statusCode = status;
    result.body = data;

    return result;
}

+ (YCHttpResponse *)send:(NSURLRequest *)request {
    if (request == nil) {
        YCHttpResponse *result = [[YCHttpResponse alloc] init];

        result.error = YCHttpMakeError(1, @"Запрос не собран");

        return result;
    }

    BOOL reused = NO;
    YCHttpResponse *result = [self attempt:request redirects:0 reused:&reused];

    /**
     * Соединение из пула могло быть закрыто сервером, пока лежало без дела.
     * Узнаём мы об этом только на обрыве — тогда пробуем ещё раз, уже
     * с новым: для вызывающего это должно выглядеть как один запрос.
     */
    if (result.error != nil && reused) {
        NSLog(@"[YClients/HTTP] Соединение из пула не сработало — пробуем заново");

        result = [self attempt:request redirects:0 reused:NULL];
    }

    return result;
}

+ (void)dropPooledConnections {
    YCHttpDropPool();
}

@end
