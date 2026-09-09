/**
 * Транспорт cYclients поверх NSURLConnection.
 *
 * Библиотека обращается к сети ровно одной функцией — curl_transport_exec, —
 * и в её собственной сборке эта функция написана на libcurl. Здесь стоит
 * файл с той же сигнатурой, а src/curl_transport.c в сборку не идёт вовсе
 * (см. CYC_SOURCES в Makefile): компоновщик берёт то, что есть, и вся
 * библиотека, ни строчки о том не зная, начинает ходить через YCHttp.
 *
 * Зачем. libcurl под iOS — это своя сборка под armv7 и arm64, свой TLS
 * (Secure Transport или притащенный OpenSSL), своя связка корней и лишние
 * полтора мегабайта в бинарнике. Всё это ради работы, которую NSURLConnection
 * делает сама, — и делает через ту же Secure Transport, что и весь остальной
 * iOS. Заодно проверка сертификатов оказывается там же, где ей место:
 * одна на приложение, в YCHttp.
 *
 * Что здесь **не** меняется по сравнению с оригиналом:
 *
 *   * возвращается код ответа HTTP, а -1 означает, что ответа не было вовсе;
 *   * *json заполняется только при `success: true` в теле — на этом построен
 *     разбор во всех вызывающих файлах библиотеки;
 *   * заголовки те же самые, включая Accept с версией API.
 *
 * Дерево cJSON отдаётся во владение вызывающему: его освобождает библиотека.
 */

#import <Foundation/Foundation.h>

#import "YCHttp.h"
#import "YCTransport.h"

#include "cJSON.h"
#include "curl_transport.h"

#include <locale.h>

/**
 * Последнее пояснение сервера к отказу — см. YCTransport.h.
 *
 * Обычная переменная без замка: писать сюда может только поток очереди
 * YCApi, а он один и тот же, и на нём же значение читается.
 */
static NSString *YCLastMessage = nil;

NSString *YCTransportLastMessage(void) {
    return YCLastMessage;
}

void YCTransportResetLastMessage(void) {
    YCLastMessage = nil;
}

/** Строка C → NSString; NULL и не-UTF-8 дают nil, а не падение. */
static NSString *YCString(const char *value) {
    if (value == NULL) {
        return nil;
    }

    return [NSString stringWithUTF8String:value];
}

/**
 * Адрес в NSURL.
 *
 * Обычно строка уже пригодна как есть: библиотека собирает адреса из чисел
 * и дат. Но cyclients_clients_search подставляет туда поисковый запрос —
 * с пробелами и кириллицей, — и на таком NSURL молча отдаёт nil. Поэтому
 * экранирование включается только тогда, когда простой разбор не удался:
 * применять его всегда нельзя, оно съело бы уже готовые %-последовательности
 * в повторно разбираемом адресе.
 */
static NSURL *YCURL(NSString *string) {
    NSURL *url = [NSURL URLWithString:string];

    if (url != nil) {
        return url;
    }

    NSString *escaped =
        [string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    return escaped != nil ? [NSURL URLWithString:escaped] : nil;
}

/**
 * Разбирает строку заголовка «Имя: значение».
 *
 * Библиотека передаёт заголовок авторизации одной готовой строкой — так
 * его требует curl_slist_append. Двоеточие ищется первое: в значении оно
 * встречается («Bearer xxx, User yyy» не содержит, но полагаться на это
 * незачем), а в имени заголовка — нет.
 */
static void YCApplyHeader(NSMutableURLRequest *request, NSString *line) {
    if ([line length] == 0) {
        return;
    }

    NSRange colon = [line rangeOfString:@":"];

    if (colon.location == NSNotFound) {
        NSLog(@"[YClients/HTTP] Заголовок без двоеточия пропущен: %@", line);
        return;
    }

    NSString *name = [line substringToIndex:colon.location];
    NSString *value = [[line substringFromIndex:colon.location + 1]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    [request setValue:value forHTTPHeaderField:name];
}

HTTP_RESPONCE
curl_transport_exec(const char *request_url,
                    const char *auth_header,
                    const char *http_method,
                    const char *post_data,
                    cJSON **json) {
    @autoreleasepool {
        if (request_url == NULL || http_method == NULL) {
            return -1;
        }

        /**
         * Разделитель дробной части — точка, а не запятая.
         *
         * cJSON печатает и разбирает числа через sprintf/strtod, а те
         * смотрят на текущую локаль. Под русской локалью «12.5» разобралось
         * бы как 12, а цена услуги ушла бы на сервер как «12,5» — то есть
         * сломанным JSON. Строка перенесена из оригинального транспорта
         * дословно и по той же причине.
         */
        setlocale(LC_NUMERIC, "C");

        NSString *urlString = YCString(request_url);
        NSString *method = YCString(http_method);

        NSMutableURLRequest *request = nil;
        NSURL *url = urlString != nil ? YCURL(urlString) : nil;

        if (url != nil) {
            request = [YCNetworkClass(@"NSMutableURLRequest") requestWithURL:url
                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                timeoutInterval:30.0];

            [request setHTTPMethod:method];
        }

        if (request == nil) {
            NSLog(@"[YClients/HTTP] Адрес не разобран: %@", urlString ?: @"(нет)");
            return -1;
        }

        NSLog(@"[YClients/HTTP] %@ %@", method, urlString);

        // Версия API задаётся заголовком Accept — без неё сервер отвечает
        // первой версией, где у записей другие имена полей.
        [request setValue:@"application/vnd.yclients.v2+json" forHTTPHeaderField:@"Accept"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

        YCApplyHeader(request, YCString(auth_header));

        if (post_data != NULL) {
            NSData *body = [YCString(post_data) dataUsingEncoding:NSUTF8StringEncoding];

            [request setHTTPBody:body];

            // Длину проставляет сама NSURLConnection; заголовок Connection
            // не ставим вовсе — оригинал просил «close», но переиспользование
            // соединения здесь как раз желательно: каждое новое стоит
            // рукопожатия TLS, а на iPhone 4 это самая долгая часть запроса.
            NSLog(@"[YClients/HTTP] Тело: %@", YCString(post_data));
        }

        YCHttpResponse *response = [YCHttp send:request];

        if (response.error != nil) {
            NSLog(@"[YClients/HTTP] Ошибка сети: %@", [response.error localizedDescription]);

            /**
             * Сетевой отказ тоже должен дойти до экрана.
             *
             * Библиотека возвращает наружу один только код, и вызывающий
             * не отличает «сервер сказал: записей нет» от «до сервера
             * не дошли». Без этой строки день без связи показывался бы
             * как день без записей — а это прямой путь к двойной записи
             * на одно время.
             */
            if ([response.error code] == NSURLErrorUserCancelledAuthentication) {
                /**
                 * Это не отказ пользователя, а наш собственный: так
                 * выглядит цепочка сертификатов, которую мы не приняли.
                 * На iOS 6 это самый вероятный отказ из всех, и объяснить
                 * его надо словами — иначе он неотличим от обрыва связи.
                 */
                YCLastMessage = @"Не удалось проверить подлинность сервера. "
                                @"Проверьте дату и время на устройстве; "
                                @"подробности — в журнале приложения.";
            } else {
                YCLastMessage = [NSString stringWithFormat:@"Нет связи с сервером: %@",
                                                           [response.error localizedDescription]];
            }

            // Код ответа отдаём, если он всё-таки успел прийти: по нему
            // библиотека отличает 401 от обрыва связи.
            return response.statusCode > 0 ? (HTTP_RESPONCE)response.statusCode : -1;
        }

        NSLog(@"[YClients/HTTP] Код %ld, тело %lu Б",
              (long)response.statusCode, (unsigned long)[response.body length]);

        HTTP_RESPONCE code = (HTTP_RESPONCE)response.statusCode;

        /**
         * Отказ без тела всё равно должен что-то сказать.
         *
         * 401 с пустым ответом — обычное дело для отозванного токена,
         * и «записей нет» вместо «войдите заново» отправляет разбираться
         * не туда. Пояснение общее, но с кодом: по нему в журнале
         * находится нужный запрос.
         */
        if (code >= 400) {
            YCLastMessage = [NSString stringWithFormat:
                (code == 401 || code == 403)
                    ? @"Сервер отказал в доступе (код %ld). Возможно, "
                      @"токен устарел — войдите заново."
                    : @"Сервер ответил кодом %ld.",
                (long)code];
        }

        if ([response.body length] == 0) {
            return code;
        }

        /**
         * Разбор идёт по длине, а не по завершающему нулю: тело — это NSData,
         * и нуля в конце у него нет. cJSON_ParseWithLength для того и есть.
         */
        cJSON *parsed = cJSON_ParseWithLength((const char *)[response.body bytes],
                                              [response.body length]);

        if (parsed == NULL) {
            NSString *text = [[NSString alloc] initWithData:response.body
                                                   encoding:NSUTF8StringEncoding];

            // Первые двести знаков: этого хватает, чтобы увидеть страницу
            // с ошибкой вместо JSON, и не хватает, чтобы залить журнал.
            NSLog(@"[YClients/HTTP] Тело не разобрано как JSON: %@",
                  [text length] > 200 ? [text substringToIndex:200] : (text ?: @"(не UTF-8)"));
            return code;
        }

        if (!cJSON_IsObject(parsed)) {
            cJSON_Delete(parsed);
            return code;
        }

        cJSON *success = cJSON_GetObjectItem(parsed, "success");

        if (cJSON_IsTrue(success)) {
            if (json != NULL) {
                // Дерево уходит во владение библиотеке — она его и удалит.
                *json = parsed;
            } else {
                cJSON_Delete(parsed);
            }

            return code;
        }

        /**
         * success: false — сервер объяснил отказ в meta.
         *
         * Это единственное место, где видно, **почему** не сохранилась
         * запись: «время занято», «нет прав», «неверный формат телефона».
         * Без этой строки в интерфейсе остаётся только код ответа, а он
         * у всех перечисленных случаев один и тот же.
         */
        cJSON *meta = cJSON_GetObjectItem(parsed, "meta");

        if (cJSON_IsObject(meta)) {
            char *text = cJSON_PrintUnformatted(meta);

            if (text != NULL) {
                NSLog(@"[YClients/HTTP] Отказ: %s", text);
                cJSON_free(text);
            }

            /**
             * Настоящая причина лежит в meta.errors, а не в meta.message.
             *
             * Сервер отвечает на отказ парой: message — общее «Произошла
             * ошибка», errors — разбор по полям, вроде
             * `{"services":["Не передан обязательный параметр services."]}`.
             * Показывать первое без второго значит показывать, что что-то
             * не так, и умалчивать, что именно; ровно на этом и потерялся
             * день при первой попытке создать запись.
             *
             * Поэтому берём разбор по полям, а общее сообщение остаётся
             * запасным вариантом.
             */
            NSMutableArray *details = [NSMutableArray array];

            cJSON *errors = cJSON_GetObjectItem(meta, "errors");

            if (cJSON_IsObject(errors)) {
                cJSON *field = NULL;

                cJSON_ArrayForEach(field, errors) {
                    // Значение поля бывает и массивом строк, и строкой.
                    if (cJSON_IsArray(field)) {
                        cJSON *line = NULL;

                        cJSON_ArrayForEach(line, field) {
                            if (cJSON_IsString(line) && line->valuestring != NULL) {
                                [details addObject:YCString(line->valuestring)];
                            }
                        }
                    } else if (cJSON_IsString(field) && field->valuestring != NULL) {
                        [details addObject:YCString(field->valuestring)];
                    }
                }
            }

            if ([details count] > 0) {
                YCLastMessage = [details componentsJoinedByString:@"\n"];
            } else {
                cJSON *message = cJSON_GetObjectItem(meta, "message");

                if (cJSON_IsString(message) && message->valuestring != NULL) {
                    YCLastMessage = YCString(message->valuestring);
                }
            }
        } else {
            NSLog(@"[YClients/HTTP] Отказ без пояснения, код %ld", (long)code);
        }

        cJSON_Delete(parsed);

        return code;
    }
}
