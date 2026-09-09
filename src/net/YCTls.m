#import "YCTls.h"

#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>

NSString *const YCTlsErrorDomain = @"ru.computershik.yclients.tls";
const NSInteger YCTlsReadTimedOut = -2;

static SSL_CTX *gContext = NULL;
static NSInteger gRoots = 0;

@implementation YCTls {
    NSString *_host;
    uint16_t  _port;
    int       _socket;
    SSL      *_ssl;
}

@synthesize protocolName = _protocolName;
@synthesize cipherName = _cipherName;
@synthesize peerSubject = _peerSubject;
@synthesize peerIssuer = _peerIssuer;

#pragma mark - Подготовка библиотеки

/**
 * Корни доверия — свои, из связки.
 *
 * Обычный набор Mozilla (Resources/certs/roots.pem, около полутора сотен
 * центров), а не выборка под сегодняшний сертификат api.yclients.com:
 * какой центр там окажется завтра, мы отсюда не знаем, а полный набор
 * переживёт смену издателя, не требуя новой сборки.
 *
 * Системное хранилище остаётся в стороне намеренно. На iOS 6 оно застыло
 * в 2012 году: там нет ни ISRG Root X1, ни новых GlobalSign, и добавить
 * туда нечего.
 *
 * Отдельные файлы .der из того же каталога добавляются сверху — это путь
 * для корня перехватчика вроде Charles, если кто-то захочет оставить
 * проверку включённой.
 */
static NSInteger YCTlsLoadRoots(SSL_CTX *ctx) {
    NSInteger loaded = 0;

    NSString *bundle = [[NSBundle mainBundle] pathForResource:@"roots"
                                                       ofType:@"pem"
                                                  inDirectory:@"certs"];

    if (bundle != nil) {
        // load_verify_locations, а не load_verify_file: последняя появилась
        // только в OpenSSL 3.0, а у нас 1.1.1.
        if (SSL_CTX_load_verify_locations(ctx, bundle.UTF8String, NULL) == 1) {
            X509_STORE *store = SSL_CTX_get_cert_store(ctx);

            loaded = store != NULL ? sk_X509_OBJECT_num(X509_STORE_get0_objects(store)) : 0;
        } else {
            NSLog(@"[YClients/TLS] Набор корней не прочитан: %@", bundle);
        }
    } else {
        NSLog(@"[YClients/TLS] В связке нет certs/roots.pem");
    }

    X509_STORE *store = SSL_CTX_get_cert_store(ctx);

    for (NSString *path in [[NSBundle mainBundle] pathsForResourcesOfType:@"der"
                                                              inDirectory:@"certs"]) {
        NSData *data = [NSData dataWithContentsOfFile:path];

        if ([data length] == 0 || store == NULL) {
            continue;
        }

        const unsigned char *bytes = (const unsigned char *)[data bytes];
        X509 *cert = d2i_X509(NULL, &bytes, (long)[data length]);

        if (cert == NULL) {
            NSLog(@"[YClients/TLS] Не разобрался корень %@", [path lastPathComponent]);
            continue;
        }

        if (X509_STORE_add_cert(store, cert)) {
            loaded++;
        }

        X509_free(cert);
    }

    return loaded;
}

+ (void)prepare {
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        SSL_library_init();
        SSL_load_error_strings();

        // TLS_client_method — «любая версия, договоримся по ходу».
        // Нижняя граница задаётся отдельно: ниже TLS 1.2 сервер и сам
        // не пойдёт, а клиент, предлагающий протокол из девяностых,
        // сам себя объявляет подозрительным.
        gContext = SSL_CTX_new(TLS_client_method());

        if (gContext == NULL) {
            NSLog(@"[YClients/TLS] Контекст не создался");
            return;
        }

        SSL_CTX_set_min_proto_version(gContext, TLS1_2_VERSION);

        SSL_CTX_set_verify(gContext, SSL_VERIFY_PEER, NULL);
        SSL_CTX_set_verify_depth(gContext, 6);

        // Сжатие TLS выключено: оно давно признано опасным (CRIME),
        // и нынешние клиенты его не предлагают.
        SSL_CTX_set_options(gContext, SSL_OP_NO_COMPRESSION);

        /**
         * Набор шифров — как у нынешних мобильных приложений.
         *
         * Порядок здесь такая же примета клиента, как и User-Agent.
         * Важно, что список наш, а не системный: именно из-за набора
         * шифров эпохи iOS 6 рукопожатие с сервером 2026 года могло
         * не состояться вовсе.
         */
        SSL_CTX_set_cipher_list(gContext,
            "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:"
            "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:"
            "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:"
            "ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:AES128-GCM-SHA256");

        SSL_CTX_set_ciphersuites(gContext,
            "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256");

        gRoots = YCTlsLoadRoots(gContext);

        NSLog(@"[YClients/TLS] %s, корней загружено: %ld",
              OpenSSL_version(OPENSSL_VERSION), (long)gRoots);

        if (gRoots == 0) {
            NSLog(@"[YClients/TLS] ВНИМАНИЕ: ни одного корня — проверки провалятся");
        }
    });
}

+ (NSInteger)loadedRootCount {
    [self prepare];

    return gRoots;
}

+ (NSString *)libraryVersion {
    [self prepare];

    return [NSString stringWithUTF8String:OpenSSL_version(OPENSSL_VERSION)];
}

#pragma mark - Жизненный цикл

- (id)initWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];

    if (self != nil) {
        _host = [host copy];
        _port = port;
        _socket = -1;
    }

    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (_ssl != NULL) {
        // Одного вызова достаточно: дожидаться ответного «до свидания»
        // незачем — соединение мы и так закрываем.
        SSL_shutdown(_ssl);
        SSL_free(_ssl);
        _ssl = NULL;
    }

    if (_socket >= 0) {
        close(_socket);
        _socket = -1;
    }
}

#pragma mark - Ошибки

static NSError *YCTlsMakeError(YCTlsErrorCode code, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    return [NSError errorWithDomain:YCTlsErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: text }];
}

/**
 * Последняя ошибка OpenSSL человеческими словами.
 *
 * Очередь разгребается до конца: иначе следующая операция увидит чужую
 * запись и объяснит происходящее совершенно неверно.
 */
static NSString *YCTlsOpenSSLError(void) {
    NSMutableArray *lines = [NSMutableArray array];
    unsigned long code;

    while ((code = ERR_get_error()) != 0) {
        char buffer[256];

        ERR_error_string_n(code, buffer, sizeof(buffer));
        [lines addObject:[NSString stringWithUTF8String:buffer]];
    }

    return [lines count] > 0 ? [lines componentsJoinedByString:@"; "] : @"нет подробностей";
}

#pragma mark - Сокет

/**
 * Подключение с тайм-аутом: сокет переводится в неблокирующий режим,
 * connect возвращает управление сразу, а ждём мы на select.
 *
 * Без этого приложение на плохой связи замирает до системного тайм-аута,
 * а он на iOS около минуты с четвертью.
 */
static int YCTlsConnectWithTimeout(struct addrinfo *address, NSTimeInterval timeout) {
    int fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);

    if (fd < 0) {
        return -1;
    }

    int flags = fcntl(fd, F_GETFL, 0);

    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    int one = 1;

    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    // Обрыв соединения не должен убивать процесс сигналом.
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

    if (connect(fd, address->ai_addr, address->ai_addrlen) == 0) {
        fcntl(fd, F_SETFL, flags);
        return fd;
    }

    if (errno != EINPROGRESS) {
        close(fd);
        return -1;
    }

    fd_set writable;

    FD_ZERO(&writable);
    FD_SET(fd, &writable);

    struct timeval tv;

    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = (suseconds_t)((timeout - (NSTimeInterval)tv.tv_sec) * 1000000);

    if (select(fd + 1, NULL, &writable, NULL, &tv) <= 0) {
        close(fd);
        return -1;
    }

    // select сказал «можно писать», но это ещё не «подключено»: так же он
    // ведёт себя и при отказе. Настоящий ответ лежит в SO_ERROR.
    int soError = 0;
    socklen_t length = sizeof(soError);

    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length) < 0 || soError != 0) {
        close(fd);
        return -1;
    }

    fcntl(fd, F_SETFL, flags);

    return fd;
}

/** Открывает сокет к указанному узлу, перебирая все его адреса. */
- (int)openSocketTo:(NSString *)host port:(uint16_t)port
            timeout:(NSTimeInterval)timeout error:(NSError **)error {
    struct addrinfo hints;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;          // и IPv4, и IPv6
    hints.ai_socktype = SOCK_STREAM;

    // AI_ADDRCONFIG — не спрашивать адреса того семейства, которого
    // на устройстве нет: иначе в сети без IPv6 резолвер всё равно ходит
    // за AAAA и ждёт своего тайм-аута.
    hints.ai_flags = AI_ADDRCONFIG;

    struct addrinfo *list = NULL;
    NSString *portText = [NSString stringWithFormat:@"%u", (unsigned)port];
    NSDate *started = [NSDate date];

    int rc = getaddrinfo([host UTF8String], [portText UTF8String], &hints, &list);

    if (rc != 0 || list == NULL) {
        NSLog(@"[YClients/TLS] %@: имя не разрешилось за %.1f с — %s",
              host, -[started timeIntervalSinceNow], gai_strerror(rc));

        if (error) {
            *error = YCTlsMakeError(YCTlsErrorResolve, @"не разрешилось имя %@: %s",
                                    host, gai_strerror(rc));
        }

        return -1;
    }

    int fd = -1;

    for (struct addrinfo *a = list; a != NULL; a = a->ai_next) {
        fd = YCTlsConnectWithTimeout(a, timeout);

        if (fd >= 0) {
            break;
        }

        NSLog(@"[YClients/TLS] %@: адрес не подошёл (errno %d)", host, errno);
    }

    freeaddrinfo(list);

    if (fd < 0 && error) {
        *error = YCTlsMakeError(YCTlsErrorConnect, @"не подключился к %@:%u",
                                host, (unsigned)port);
    }

    return fd;
}

/**
 * Туннель через прокси: CONNECT узел:порт, ждём «200».
 *
 * Делается до всякого TLS и обычным текстом — так и задумано протоколом:
 * прокси должен знать, куда вести трубу, а внутри трубы уже наше
 * шифрование, которое он не читает (пока не подменит сертификат, ради чего
 * рядом и стоит insecure).
 */
- (BOOL)openTunnelThroughProxyWithTimeout:(NSTimeInterval)timeout error:(NSError **)error {
    NSString *request = [NSString stringWithFormat:
        @"CONNECT %@:%u HTTP/1.1\r\nHost: %@:%u\r\nProxy-Connection: keep-alive\r\n\r\n",
        _host, (unsigned)_port, _host, (unsigned)_port];

    NSData *data = [request dataUsingEncoding:NSUTF8StringEncoding];

    if (send(_socket, [data bytes], [data length], 0) < 0) {
        if (error) {
            *error = YCTlsMakeError(YCTlsErrorProxy, @"прокси не принял запрос (errno %d)", errno);
        }

        return NO;
    }

    struct timeval tv;

    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = 0;
    setsockopt(_socket, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    // Ответ читается по одному байту до пустой строки. Медленно, но здесь
    // это десятки байт один раз за соединение, зато ни один байт тела
    // не будет случайно проглочен: дальше по этой же трубе пойдёт TLS,
    // и лишний прочитанный байт сломал бы рукопожатие.
    NSMutableData *head = [NSMutableData data];
    uint8_t byte = 0;

    while ([head length] < 4096) {
        ssize_t got = recv(_socket, &byte, 1, 0);

        if (got <= 0) {
            if (error) {
                *error = YCTlsMakeError(YCTlsErrorProxy, @"прокси оборвал ответ");
            }

            return NO;
        }

        [head appendBytes:&byte length:1];

        const char *bytes = (const char *)[head bytes];
        NSUInteger length = [head length];

        if (length >= 4 && memcmp(bytes + length - 4, "\r\n\r\n", 4) == 0) {
            break;
        }
    }

    NSString *answer = [[NSString alloc] initWithData:head encoding:NSISOLatin1StringEncoding];
    NSArray *parts = [answer componentsSeparatedByString:@" "];
    NSInteger status = [parts count] > 1 ? [[parts objectAtIndex:1] integerValue] : 0;

    if (status != 200) {
        NSString *first = [[answer componentsSeparatedByString:@"\r\n"] objectAtIndex:0];

        NSLog(@"[YClients/TLS] Прокси отказал: %@", first);

        if (error) {
            *error = YCTlsMakeError(YCTlsErrorProxy, @"прокси отказал: %@", first);
        }

        return NO;
    }

    NSLog(@"[YClients/TLS] Туннель через %@:%u открыт", self.proxyHost, (unsigned)self.proxyPort);

    return YES;
}

#pragma mark - Соединение

- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error {
    [YCTls prepare];

    if (gContext == NULL) {
        if (error) {
            *error = YCTlsMakeError(YCTlsErrorHandshake, @"криптография не поднялась");
        }

        return NO;
    }

    NSDate *started = [NSDate date];

    BOOL throughProxy = [self.proxyHost length] > 0 && self.proxyPort > 0;

    // Сокет открывается либо прямо к серверу, либо к прокси — и тогда
    // до сервера пробивается туннель.
    _socket = throughProxy
        ? [self openSocketTo:self.proxyHost port:self.proxyPort timeout:timeout error:error]
        : [self openSocketTo:_host port:_port timeout:timeout error:error];

    if (_socket < 0) {
        return NO;
    }

    if (throughProxy && ![self openTunnelThroughProxyWithTimeout:timeout error:error]) {
        [self close];
        return NO;
    }

    NSLog(@"[YClients/TLS] %@:%u: сокет открыт за %.1f с, рукопожатие…",
          _host, (unsigned)_port, -[started timeIntervalSinceNow]);

    // Дальше работаем блокирующе, но с тайм-аутом на каждой операции —
    // иначе молчащий сервер держал бы поток вечно.
    [self setReadTimeout:timeout];

    struct timeval tv;

    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = 0;
    setsockopt(_socket, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    _ssl = SSL_new(gContext);

    if (_ssl == NULL) {
        if (error) {
            *error = YCTlsMakeError(YCTlsErrorHandshake, @"SSL_new: %@", YCTlsOpenSSLError());
        }

        return NO;
    }

    SSL_set_fd(_ssl, _socket);

    // Имя узла в расширении SNI. Без него сервер, держащий на одном адресе
    // сотни имён, покажет чужой сертификат — а мы его не примем.
    SSL_set_tlsext_host_name(_ssl, [_host UTF8String]);

    if (self.insecure) {
        SSL_set_verify(_ssl, SSL_VERIFY_NONE, NULL);
    } else {
        // Имя узла для проверки — отдельная работа: цепочка может быть
        // безупречной, но выписанной на другой домен.
        X509_VERIFY_PARAM *param = SSL_get0_param(_ssl);

        X509_VERIFY_PARAM_set_hostflags(param, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);

        if (!X509_VERIFY_PARAM_set1_host(param, [_host UTF8String], 0)) {
            if (error) {
                *error = YCTlsMakeError(YCTlsErrorHandshake, @"не задалось имя для проверки");
            }

            return NO;
        }
    }

    // ALPN: говорим, что умеем HTTP/1.1. Просить h2 не станем — своей
    // реализации HTTP/2 у нас нет.
    static const unsigned char alpn[] = { 8, 'h','t','t','p','/','1','.','1' };

    SSL_set_alpn_protos(_ssl, alpn, sizeof(alpn));

    NSDate *shaking = [NSDate date];

    if (SSL_connect(_ssl) != 1) {
        long verify = SSL_get_verify_result(_ssl);
        NSString *details = YCTlsOpenSSLError();

        NSLog(@"[YClients/TLS] %@: рукопожатие не вышло за %.1f с (errno %d, проверка %ld)",
              _host, -[shaking timeIntervalSinceNow], errno, verify);

        if (error) {
            *error = verify != X509_V_OK
                ? YCTlsMakeError(YCTlsErrorCertificate, @"сертификат не принят: %s",
                                 X509_verify_cert_error_string(verify))
                : YCTlsMakeError(YCTlsErrorHandshake, @"рукопожатие не состоялось: %@", details);
        }

        return NO;
    }

    _protocolName = [NSString stringWithUTF8String:SSL_get_version(_ssl)];
    _cipherName = [NSString stringWithUTF8String:
        SSL_CIPHER_get_name(SSL_get_current_cipher(_ssl))];

    NSLog(@"[YClients/TLS] %@:%u — %@, %@ (всего %.1f с)", _host, (unsigned)_port,
          _protocolName, _cipherName, -[started timeIntervalSinceNow]);

    X509 *peer = SSL_get_peer_certificate(_ssl);

    if (peer != NULL) {
        char line[512];

        X509_NAME_oneline(X509_get_subject_name(peer), line, sizeof(line));
        _peerSubject = [NSString stringWithUTF8String:line];

        X509_NAME_oneline(X509_get_issuer_name(peer), line, sizeof(line));
        _peerIssuer = [NSString stringWithUTF8String:line];

        X509_free(peer);
    }

    return YES;
}

- (void)setReadTimeout:(NSTimeInterval)timeout {
    if (_socket < 0) {
        return;
    }

    struct timeval tv;

    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = (suseconds_t)((timeout - (NSTimeInterval)tv.tv_sec) * 1000000);

    setsockopt(_socket, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
}

#pragma mark - Обмен

- (NSInteger)writeBytes:(const void *)bytes length:(NSUInteger)length error:(NSError **)error {
    if (_ssl == NULL) {
        if (error) {
            *error = YCTlsMakeError(YCTlsErrorIO, @"соединение закрыто");
        }

        return -1;
    }

    NSUInteger sent = 0;

    while (sent < length) {
        int written = SSL_write(_ssl, (const char *)bytes + sent, (int)(length - sent));

        if (written <= 0) {
            int reason = SSL_get_error(_ssl, written);

            // WANT_READ при записи — не ошибка, а пересогласование ключей:
            // библиотеке нужно прочитать ответ сервера. Сокет блокирующий,
            // так что просто пробуем снова.
            if (reason == SSL_ERROR_WANT_READ || reason == SSL_ERROR_WANT_WRITE) {
                continue;
            }

            if (error) {
                *error = YCTlsMakeError(YCTlsErrorIO, @"обрыв при отправке: %@",
                                        YCTlsOpenSSLError());
            }

            return -1;
        }

        sent += (NSUInteger)written;
    }

    return (NSInteger)sent;
}

- (NSInteger)readBytes:(void *)buffer maxLength:(NSUInteger)length error:(NSError **)error {
    if (_ssl == NULL) {
        if (error) {
            *error = YCTlsMakeError(YCTlsErrorIO, @"соединение закрыто");
        }

        return -1;
    }

    while (1) {
        errno = 0;

        int got = SSL_read(_ssl, buffer, (int)length);

        if (got > 0) {
            return got;
        }

        int reason = SSL_get_error(_ssl, got);

        // Тайм-аут на сокете: данных пока нет, но соединение живо.
        if ((reason == SSL_ERROR_SYSCALL || reason == SSL_ERROR_WANT_READ)
            && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            return YCTlsReadTimedOut;
        }

        // Ноль означает конец: либо сервер попрощался по правилам,
        // либо просто закрыл соединение.
        if (reason == SSL_ERROR_ZERO_RETURN) {
            return 0;
        }

        if (reason == SSL_ERROR_SYSCALL && errno == 0) {
            return 0;
        }

        if (reason == SSL_ERROR_WANT_READ || reason == SSL_ERROR_WANT_WRITE) {
            continue;
        }

        if (error) {
            *error = YCTlsMakeError(YCTlsErrorIO, @"обрыв при чтении: %@", YCTlsOpenSSLError());
        }

        return -1;
    }
}

@end
