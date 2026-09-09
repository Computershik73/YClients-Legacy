#import <Foundation/Foundation.h>

/**
 * Защищённое соединение поверх сокета, на своей криптографии (OpenSSL).
 *
 * Перенесено из Max-iOS, где тот же слой решает ту же беду.
 *
 * **Зачем.** Всё это система умеет и сама — но по-своему в каждой версии.
 * От iOS 6 до нынешней в Secure Transport сменились и набор шифров,
 * и поддерживаемые версии протокола, и хранилище корней. На iPad 2 с iOS 6
 * вход в YClients просто висел до тайм-аута: рукопожатие не состаивалось
 * вовсе, и отличить это от «нет сети» было нечем. Причин у такого отказа
 * две, и обе неисправимы со стороны приложения, пока TLS системный:
 *
 *   * хранилище корней iOS 6 застыло в 2012 году. Ни ISRG Root X1
 *     (Let's Encrypt, 2015), ни новых GlobalSign, ни российских корней там
 *     нет и не появится;
 *   * набор шифров той поры сервер 2026 года может не принять вовсе.
 *
 * Своя библиотека ведёт себя одинаково везде: разговор с сервером выглядит
 * так, как задали мы, а не так, как решил планшет 2011 года. Корни едут
 * в связке (Resources/certs/roots.pem — обычный набор Mozilla).
 *
 * Работает синхронно и блокирующе, и это нарочно: асинхронность здесь была
 * бы третьей по счёту — у сокета своя, у OpenSSL своя, у вызывающего своя.
 * YCHttp зовёт нас с очереди YCApi, где ждать можно.
 */

extern NSString *const YCTlsErrorDomain;

typedef enum {
    YCTlsErrorResolve = 1,      // имя не разрешилось
    YCTlsErrorConnect,          // сокет не подключился
    YCTlsErrorProxy,            // прокси не открыл туннель
    YCTlsErrorHandshake,        // рукопожатие не состоялось
    YCTlsErrorCertificate,      // сертификат не принят
    YCTlsErrorIO                // обрыв или тайм-аут при обмене
} YCTlsErrorCode;

/** Возврат из чтения, когда данных пока нет, а соединение живо. */
extern const NSInteger YCTlsReadTimedOut;

@interface YCTls : NSObject

/** Один раз за запуск: инициализация библиотеки и загрузка корней. */
+ (void)prepare;

/** Сколько корней удалось загрузить — показывается в «О программе». */
+ (NSInteger)loadedRootCount;

/** Название и версия библиотеки — туда же. */
+ (NSString *)libraryVersion;

- (id)initWithHost:(NSString *)host port:(uint16_t)port;

/**
 * Прокси для отладки: адрес и порт HTTP-прокси.
 *
 * Соединение тогда открывается к нему, а до сервера пробивается
 * туннель CONNECT — то есть перехватчик видит запросы, а мы всё равно
 * говорим по своему TLS. Своими силами это работает на **всех** версиях
 * системы; прежняя реализация на NSURLSession требовала iOS 7 и на iPad 2
 * была недоступна вовсе.
 */
@property (nonatomic, copy) NSString *proxyHost;
@property (nonatomic, assign) uint16_t proxyPort;

/**
 * Не проверять цепочку вовсе.
 *
 * Включается вместе с прокси: перехватчик подменяет сертификат своим,
 * и честная проверка его отвергнет. Соединение остаётся шифрованным,
 * но беззащитным к перехвату — в этом и смысл.
 */
@property (nonatomic, assign) BOOL insecure;

/** Подключается и проводит рукопожатие. Тайм-аут общий на обе операции. */
- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/** Тайм-аут ожидания данных при чтении. Ноль — ждать сколько придётся. */
- (void)setReadTimeout:(NSTimeInterval)timeout;

- (NSInteger)writeBytes:(const void *)bytes length:(NSUInteger)length error:(NSError **)error;

/**
 * Больше нуля — прочитано; ноль — сервер закрыл соединение;
 * YCTlsReadTimedOut — данных пока нет; минус один — ошибка.
 */
- (NSInteger)readBytes:(void *)buffer maxLength:(NSUInteger)length error:(NSError **)error;

- (void)close;

/** Заполняются после успешного рукопожатия — первое, что смотрят в журнале. */
@property (nonatomic, readonly) NSString *protocolName;   // TLSv1.3
@property (nonatomic, readonly) NSString *cipherName;
@property (nonatomic, readonly) NSString *peerSubject;
@property (nonatomic, readonly) NSString *peerIssuer;

@end
