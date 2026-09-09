#import <Foundation/Foundation.h>

/**
 * Собирает запрос.
 *
 * Казалось бы, ради этого не нужна отдельная функция — но нужна, и вот
 * почему. Мы собираемся против SDK 9.3, а работать должны начиная с iOS 6,
 * и за эти версии Apple переселила всё семейство NSURL из Foundation
 * в CFNetwork. Компоновщик при двухуровневом пространстве имён записывает
 * в бинарник не просто имя символа, а «искать в такой-то библиотеке» — и
 * берёт эту библиотеку из SDK. Получается ссылка на NSMutableURLRequest
 * «в CFNetwork», а на iOS 6 и 7 этот класс лежит в Foundation, и приложение
 * не запускается вовсе:
 *
 *     Symbol not found: _NSURLAuthenticationMethodServerTrust
 *     Expected in: /System/Library/Frameworks/CFNetwork.framework/CFNetwork
 *
 * Отказ этот — не падение, а отказ загрузчика: он случается до main,
 * и в журнале падений от него не остаётся ничего.
 *
 * Лечится тем, что ссылки на классы этого семейства заменены на поиск
 * по имени через рантайм: тогда в бинарнике нет ни символа, ни привязки
 * к библиотеке, а класс находится там, где он на этой системе и лежит.
 * Затронуты NSMutableURLRequest, NSURLConnection, NSURLCredential
 * и NSHTTPURLResponse — всё, чем мы пользуемся из переехавшего.
 *
 * Проверяется это, не доводя до устройства:
 *
 *     nm -arch armv7 -m -u .theos/obj/YClients.app/YClients | grep "(from "
 *
 * После правки в списке загружаемых библиотек CFNetwork нет вовсе.
 */
NSMutableURLRequest *YCRequest(NSString *url, NSString *method, NSTimeInterval timeout);

/** Тот же обход для классов, которые нужны по имени в других файлах. */
Class YCNetworkClass(NSString *name);


/** Ответ сервера. Тело прочитано целиком. */
@interface YCHttpResponse : NSObject

@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSData *body;

/** Сетевая ошибка; nil, если ответ пришёл — каким бы ни был его код. */
@property (nonatomic, strong) NSError *error;

@end


/**
 * Единственный HTTP-клиент приложения: через него идёт всё, что уходит
 * к api.yclients.com.
 *
 * Стоит на своём TLS (см. YCTls.h), а не на NSURLConnection. Причина
 * простая: на iPad 2 с iOS 6 вход просто висел до тайм-аута — системное
 * хранилище корней там застыло в 2012 году, а набор шифров той поры
 * сервер 2026 года может не принять вовсе. Со своей криптографией разговор
 * выглядит одинаково на всех версиях, а корни едут в связке.
 *
 * Сам по себе это полноценный клиент HTTP/1.1: заголовки, тело по длине
 * и «кусками», переадресации, пул живых соединений. Немного, но всё
 * своё — и потому предсказуемое.
 */
@interface YCHttp : NSObject

/**
 * Выполняет запрос и ждёт ответа.
 *
 * **Вызывать только с фоновой очереди**: метод блокирует поток до ответа.
 * Единственный, кто его зовёт, — YCTransport, а он работает с очереди YCApi.
 */
+ (YCHttpResponse *)send:(NSURLRequest *)request;

/** Закрыть все соединения из пула — при смене настроек прокси. */
+ (void)dropPooledConnections;

@end
