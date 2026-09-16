#import "YCApi.h"

#import "YCTime.h"
#import "YCTransport.h"

#include "cYclients.h"

NSString *const YCDidLogOutNotification = @"YCDidLogOut";
NSString *const YCShouldChooseCompanyNotification = @"YCShouldChooseCompany";

static NSString *const YCTokenKey = @"user_token";
static NSString *const YCUserNameKey = @"user_name";
static NSString *const YCCompanyIdKey = @"company_id";
static NSString *const YCCompanyTitleKey = @"company_title";

/**
 * Строка из библиотеки в NSString.
 *
 * Не просто `stringWithUTF8String:`, и вот почему. Библиотека держит строки
 * в массивах постоянной длины — `char name[64]` — и обрезает то, что не
 * влезло, по границе **байта**. Русское имя в UTF-8 занимает по два байта
 * на букву, так что обрезка приходится на середину буквы примерно в половине
 * случаев. `stringWithUTF8String:` на таком возвращает nil, и вместо
 * длинного имени в сетке оказалась бы пустота — то есть чем длиннее имя,
 * тем вероятнее, что запись выглядит безымянной.
 *
 * Поэтому при неудаче хвост отрезается по байту, пока строка не разберётся.
 * Больше трёх шагов не нужно: длиннее четырёх байт в UTF-8 символов нет.
 */
static NSString *YCStr(const char *value) {
    if (value == NULL || *value == 0) {
        return @"";
    }

    NSString *string = [NSString stringWithUTF8String:value];

    if (string != nil) {
        return string;
    }

    NSUInteger length = strlen(value);

    for (NSUInteger cut = 1; cut <= 3 && cut < length; cut++) {
        string = [[NSString alloc] initWithBytes:value
                                          length:length - cut
                                        encoding:NSUTF8StringEncoding];

        if (string != nil) {
            return string;
        }
    }

    return @"";
}

/** Телефон в том виде, в каком его хочет сервер: одни цифры. */
static NSString *YCDigits(NSString *phone) {
    NSMutableString *digits = [NSMutableString stringWithCapacity:[phone length]];

    for (NSUInteger i = 0; i < [phone length]; i++) {
        unichar c = [phone characterAtIndex:i];

        if (c >= '0' && c <= '9') {
            [digits appendFormat:@"%C", c];
        }
    }

    return digits;
}


#pragma mark - Обратные вызовы библиотеки

/**
 * Все три складывают данные в NSMutableArray, переданный через userdata.
 *
 * Перекладывание идёт здесь и только здесь: структура, на которую указывает
 * аргумент, у библиотеки одна на все элементы списка и переписывается перед
 * следующим вызовом. Сохранить указатель — значит получить список, где все
 * элементы совпадают с последним.
 *
 * Возврат нуля означает «продолжай»; обрывать перебор нам незачем.
 */
static int YCCollectCompany(void *userdata, const CYCCompany *company) {
    @autoreleasepool {
        YCCompany *item = [[YCCompany alloc] init];

        item.companyId = company->id;
        item.title = YCStr(company->title);
        item.city = YCStr(company->city);

        [(__bridge NSMutableArray *)userdata addObject:item];
    }

    return 0;
}

static int YCCollectStaff(void *userdata, const CYCStaff *staff) {
    @autoreleasepool {
        // Уволенных и скрытых не показываем: колонка на каждого, кто когда-то
        // здесь работал, съела бы всю ширину экрана.
        if (staff->fired || staff->hidden) {
            return 0;
        }

        YCStaff *item = [[YCStaff alloc] init];

        item.staffId = staff->id;
        item.name = YCStr(staff->name);
        item.specialization = YCStr(staff->specialization);
        item.seanceLength = staff->seance_length;

        [(__bridge NSMutableArray *)userdata addObject:item];
    }

    return 0;
}

static int YCCollectService(void *userdata, const CYCService *service) {
    @autoreleasepool {
        YCService *item = [[YCService alloc] init];

        item.serviceId = service->id;
        item.title = YCStr(service->title);

        // Длительность приходит под двумя именами: у каталога это duration,
        // у эндпойнта записи — seance_length. Берём то, что не ноль.
        item.duration = service->duration > 0 ? service->duration
                                              : service->seance_length;
        item.price = service->price_min;

        // Отсеивание отключённых делается уровнем выше: там видно, сколько
        // услуг всего, и есть чем распорядиться, если после отсева
        // не осталось ни одной.
        [(__bridge NSMutableArray *)userdata addObject:@[ item, @(service->active) ]];
    }

    return 0;
}

static int YCCollectRecord(void *userdata, const CYCRecord *record) {
    @autoreleasepool {
        // Удалённые записи сервер всё равно присылает; в сетке их быть
        // не должно, иначе освободившееся время выглядит занятым.
        if (record->deleted) {
            return 0;
        }

        NSDate *start = YCDateFromAPI(YCStr(record->datetime));

        if (start == nil) {
            start = YCDateFromAPI(YCStr(record->date));
        }

        if (start == nil) {
            // Без времени запись некуда положить в сетке. Молча выбросить
            // нельзя: снаружи это выглядит как пропавшая запись.
            NSLog(@"[YClients/API] Запись %d без разбираемого времени: «%s»",
                  record->id, record->datetime);
            return 0;
        }

        YCRecord *item = [[YCRecord alloc] init];

        item.recordId = record->id;
        item.staffId = record->staff_id;
        item.start = start;

        // seance_length сервер отдаёт в секундах. Ноль означает «не задано» —
        // такая запись нарисовалась бы линией нулевой высоты, в которую
        // невозможно попасть пальцем.
        item.length = record->seance_length > 0 ? record->seance_length : 3600;

        item.comment = YCStr(record->comment);
        item.attendance = record->attendance;
        item.customColor = YCStr(record->custom_color);

        item.clientId = record->client.id;

        /**
         * Имя клиента — полное, а не одно только имя.
         *
         * Сервер отдаёт готовое display_name, и оно предпочтительнее: там
         * порядок частей такой, каким его настроил филиал. Если пусто —
         * собираем сами из фамилии, имени и отчества. Раньше бралось одно
         * поле name, и в сетке все Ивановы выглядели одним Иваном.
         */
        item.clientName = YCStr(record->client.display_name);

        if ([item.clientName length] == 0) {
            item.clientName = YCJoinName(YCStr(record->client.surname),
                                         YCStr(record->client.name),
                                         YCStr(record->client.patronymic));
        }

        item.clientPhone = YCStr(record->client.phone);
        item.clientEmail = YCStr(record->client.email);

        // Услуги — второй строкой на прямоугольнике. Их бывает несколько,
        // но в высоту записи влезает одна строка, поэтому просто через
        // запятую: обрежется по ширине само.
        NSMutableArray *titles = [NSMutableArray array];
        NSMutableArray *ids = [NSMutableArray array];

        for (int i = 0; i < record->nservices; i++) {
            NSString *title = YCStr(record->services[i].title);

            if ([title length] > 0) {
                [titles addObject:title];
            }

            if (record->services[i].id > 0) {
                [ids addObject:@(record->services[i].id)];
            }
        }

        item.services = [titles componentsJoinedByString:@", "];
        item.serviceIds = ids;

        [(__bridge NSMutableArray *)userdata addObject:item];
    }

    return 0;
}


#pragma mark -

@implementation YCApi {
    dispatch_queue_t _queue;

    /**
     * Копии для очереди.
     *
     * Свойства читаются с главного потока, а библиотеке токен нужен на
     * очереди. Держать одно поле на двоих значило бы читать его в тот
     * момент, когда вход как раз переписывает его на главном, — поэтому
     * значения снимаются под замком в -snapshot.
     */
    NSString *_token;
    NSString *_userName;

    /** Запомненные сотрудники: список, время снимка и чей это филиал. */
    NSArray *_cachedStaff;
    NSDate *_cachedStaffAt;
    int _cachedStaffCompany;
    NSInteger _companyId;
    NSString *_companyTitle;
}

+ (YCApi *)shared {
    static YCApi *shared;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ shared = [[YCApi alloc] init]; });

    return shared;
}

- (id)init {
    self = [super init];

    if (self != nil) {
        _queue = dispatch_queue_create("ru.computershik.yclients.api", DISPATCH_QUEUE_SERIAL);

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        _token = [defaults stringForKey:YCTokenKey];
        _userName = [defaults stringForKey:YCUserNameKey];
        _companyId = [defaults integerForKey:YCCompanyIdKey];
        _companyTitle = [defaults stringForKey:YCCompanyTitleKey];
    }

    return self;
}

#pragma mark Состояние

- (BOOL)isAuthorized {
    @synchronized (self) { return [_token length] > 0; }
}

- (NSString *)userName {
    @synchronized (self) { return _userName ?: @""; }
}

- (NSInteger)companyId {
    @synchronized (self) { return _companyId; }
}

- (NSString *)companyTitle {
    @synchronized (self) { return _companyTitle ?: @""; }
}

/** Токен и филиал одним снимком — чтобы не читать их по одному на очереди. */
- (void)snapshotToken:(NSString **)token company:(int *)company {
    @synchronized (self) {
        *token = _token;
        *company = (int)_companyId;
    }
}

- (void)logout {
    // Кэш сотрудников привязан к филиалу и к учётной записи — при смене
    // того или другого он больше ни о чём не говорит.
    [self invalidateStaffCache];

    @synchronized (self) {
        _token = nil;
        _userName = nil;
        _companyId = 0;
        _companyTitle = nil;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    for (NSString *key in @[ YCTokenKey, YCUserNameKey, YCCompanyIdKey, YCCompanyTitleKey ]) {
        [defaults removeObjectForKey:key];
    }

    [defaults synchronize];

    NSLog(@"[YClients/API] Выход выполнен");
}

- (void)selectCompany:(YCCompany *)company {
    // Кэш сотрудников привязан к филиалу и к учётной записи — при смене
    // того или другого он больше ни о чём не говорит.
    [self invalidateStaffCache];

    @synchronized (self) {
        _companyId = company.companyId;
        _companyTitle = company.title;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setInteger:company.companyId forKey:YCCompanyIdKey];
    [defaults setObject:(company.title ?: @"") forKey:YCCompanyTitleKey];
    [defaults synchronize];

    NSLog(@"[YClients/API] Выбран филиал %ld «%@»",
          (long)company.companyId, company.title);
}

#pragma mark Служебное

/**
 * Пояснение сервера к отказу, а если его нет — своё.
 *
 * Зовётся только с очереди: YCTransportLastMessage хранит пояснение
 * последнего запроса, а «последний» имеет смысл лишь там, где запросы
 * идут по одному.
 */
- (NSString *)failureWithFallback:(NSString *)fallback {
    NSString *message = YCTransportLastMessage();

    return [message length] > 0 ? message : fallback;
}

/** Блок завершения зовётся с главного потока — всегда и без исключений. */
static void YCMain(dispatch_block_t block) {
    if (block != NULL) {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

#pragma mark Вход

- (void)loginWithLogin:(NSString *)login
              password:(NSString *)password
            completion:(void (^)(BOOL, NSString *))completion {
    dispatch_async(_queue, ^{
        @autoreleasepool {
            YCTransportResetLastMessage();

            const CYCUser *user = NULL;
            const CYC2fa *twoFactor = NULL;

            CYCLIENTS_AUTH result = cyclients_login([login UTF8String],
                                                    [password UTF8String],
                                                    &user, &twoFactor);

            if (result == CYCLIENTS_AUTH_AUTHORIZED && user != NULL) {
                NSString *token = YCStr(user->user_token);
                NSString *name = YCStr(user->name);

                if ([token length] == 0) {
                    YCMain(^{ completion(NO, @"Сервер не вернул токен"); });
                    return;
                }

                @synchronized (self) {
                    _token = token;
                    _userName = name;
                }

                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

                [defaults setObject:token forKey:YCTokenKey];
                [defaults setObject:name forKey:YCUserNameKey];
                [defaults synchronize];

                NSLog(@"[YClients/API] Вход: %@", name);

                YCMain(^{ completion(YES, nil); });
                return;
            }

            if (result == CYCLIENTS_AUTH_2FA) {
                /**
                 * Второй фактор. Библиотека его умеет, приложение — нет.
                 *
                 * Отдельный экран для кода из СМС здесь не сделан намеренно:
                 * учётная запись администратора филиала второго фактора
                 * обычно не требует, а гадать по пустому экрану, почему вход
                 * не идёт, хуже, чем прочитать эту строку.
                 */
                NSLog(@"[YClients/API] Требуется второй фактор — не поддержан");

                YCMain(^{
                    completion(NO, @"Для этой учётной записи включено "
                                   @"подтверждение по СМС. Приложение его пока "
                                   @"не умеет — отключите его в настройках "
                                   @"YClients или войдите другой учётной записью.");
                });
                return;
            }

            NSString *error = [self failureWithFallback:
                @"Не удалось войти. Проверьте логин, пароль и связь."];

            NSLog(@"[YClients/API] Вход не выполнен: %@", error);

            YCMain(^{ completion(NO, error); });
        }
    });
}

#pragma mark Филиалы и сотрудники

- (void)loadCompaniesWithCompletion:(void (^)(NSArray *, NSString *))completion {
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0) {
                YCMain(^{ completion(nil, @"Нужно войти"); });
                return;
            }

            YCTransportResetLastMessage();

            NSMutableArray *found = [NSMutableArray array];

            // NULL во втором аргументе означает «все филиалы»; из-за этого
            // же аргумента библиотека раньше падала — см. правку в companies.c.
            cyclients_companies([token UTF8String], NULL,
                                (__bridge void *)found, YCCollectCompany);

            NSLog(@"[YClients/API] Филиалов: %lu", (unsigned long)[found count]);

            if ([found count] == 0) {
                NSString *error = [self failureWithFallback:
                    @"Филиалы не получены. Проверьте связь."];

                YCMain(^{ completion(nil, error); });
                return;
            }

            YCMain(^{ completion(found, nil); });
        }
    });
}

/**
 * Сотрудники запоминаются на несколько минут.
 *
 * Их запрашивал каждый переход на другой день — а состав филиала от даты
 * не зависит. В журнале одного сеанса это четырнадцать запросов из
 * шестидесяти: четверть всего разговора с сервером уходила на то, что
 * не менялось. На iPad 2 по сотовой связи каждый такой запрос — это
 * ещё и полсекунды, в течение которых сетка пуста.
 *
 * Пять минут — срок, за который сотрудника успевают завести или уволить
 * ровно настолько редко, чтобы этого не заметить, и достаточно короткий,
 * чтобы не пришлось объяснять, почему новый сотрудник не появился.
 * Перезапуск и смена филиала сбрасывают кэш в любом случае.
 */
static const NSTimeInterval YCStaffCacheLifetime = 300.0;

- (void)invalidateStaffCache {
    @synchronized (self) {
        _cachedStaff = nil;
    }
}

- (void)loadStaffWithCompletion:(void (^)(NSArray *, NSString *))completion {
    @synchronized (self) {
        if (_cachedStaff != nil && _cachedStaffCompany == self.companyId &&
            [[NSDate date] timeIntervalSinceDate:_cachedStaffAt] < YCStaffCacheLifetime) {
            NSArray *cached = _cachedStaff;

            YCMain(^{ completion(cached, nil); });
            return;
        }
    }

    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(nil, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            NSMutableArray *found = [NSMutableArray array];

            cyclients_staff([token UTF8String], company,
                            (__bridge void *)found, YCCollectStaff);

            NSLog(@"[YClients/API] Сотрудников: %lu", (unsigned long)[found count]);

            if ([found count] > 0) {
                @synchronized (self) {
                    self->_cachedStaff = found;
                    self->_cachedStaffAt = [NSDate date];
                    self->_cachedStaffCompany = company;
                }
            }

            if ([found count] == 0) {
                NSString *error = [self failureWithFallback:
                    @"В филиале нет сотрудников, доступных для записи."];

                YCMain(^{ completion(nil, error); });
                return;
            }

            YCMain(^{ completion(found, nil); });
        }
    });
}

- (void)loadServicesForStaff:(NSInteger)staffId
                  completion:(void (^)(NSArray *, NSString *))completion {
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(nil, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            NSMutableArray *raw = [NSMutableArray array];

            /**
             * Сначала — услуги именно этого сотрудника.
             *
             * Каталог филиала для записи не годится: сервер отвечает 400
             * «Сотрудник не оказывает выбранные услуги», если услуга ему
             * не назначена. Предлагать в списке то, что заведомо будет
             * отвергнуто, — значит заставлять человека угадывать.
             */
            if (staffId > 0) {
                cyclients_book_services([token UTF8String], company, (int)staffId,
                                        (__bridge void *)raw, YCCollectService);
            }

            /**
             * Пусто у сотрудника — значит пусто, и каталог здесь не помощь.
             *
             * Раньше на этом месте стоял откат на весь каталог филиала:
             * список, часть которого сервер отвергнет, казался лучше
             * пустого. Оказалось наоборот. Сотруднику без назначенных услуг
             * подставлялась чужая, запись не создавалась, и отказ приходил
             * уже от сервера — «Сотрудник не оказывает выбранные услуги», —
             * то есть предложенное заведомо не работало.
             *
             * Каталог берётся только там, где сотрудник не задан вовсе.
             */
            if ([raw count] == 0 && staffId == 0) {
                cyclients_services([token UTF8String], company,
                                   (__bridge void *)raw, YCCollectService);
            }

            if ([raw count] == 0 && staffId > 0) {
                NSLog(@"[YClients/API] Сотруднику %ld услуги не назначены",
                      (long)staffId);

                NSString *error = [self failureWithFallback:
                    @"Этому сотруднику не назначено ни одной услуги, "
                    @"поэтому записать к нему нельзя. Назначьте услуги "
                    @"в YClients или выберите другого сотрудника."];

                YCMain(^{ completion(nil, error); });
                return;
            }

            /**
             * Отключённые услуги предлагать не нужно — но и остаться
             * без единой нельзя: без услуги запись не создать вовсе.
             *
             * Признак active приходит с сервера, и как он выставлен
             * в конкретном филиале, отсюда не проверить. Поэтому отсев
             * с оговоркой: если после него ничего не осталось, значит
             * признак означает не то, что мы думаем, и лучше показать
             * всё, чем закрыть создание записи насовсем.
             */
            NSMutableArray *active = [NSMutableArray array];
            NSMutableArray *all = [NSMutableArray array];

            for (NSArray *pair in raw) {
                [all addObject:[pair objectAtIndex:0]];

                if ([[pair objectAtIndex:1] intValue] != 0) {
                    [active addObject:[pair objectAtIndex:0]];
                }
            }

            NSArray *services = [active count] > 0 ? active : all;

            if ([active count] == 0 && [all count] > 0) {
                NSLog(@"[YClients/API] Ни одна из %lu услуг не помечена активной — "
                      @"показываем все", (unsigned long)[all count]);
            }

            // По названию: сервер отдаёт услуги в порядке своего «веса»,
            // а искать глазами в списке из полусотни удобнее по алфавиту.
            services = [services sortedArrayUsingComparator:^NSComparisonResult(YCService *a,
                                                                                YCService *b) {
                return [a.title localizedCaseInsensitiveCompare:b.title];
            }];

            NSLog(@"[YClients/API] Услуг: %lu", (unsigned long)[services count]);

            if ([services count] == 0) {
                NSString *error = [self failureWithFallback:
                    @"В филиале нет услуг. Без услуги запись создать нельзя — "
                    @"добавьте хотя бы одну в YClients."];

                YCMain(^{ completion(nil, error); });
                return;
            }

            YCMain(^{ completion(services, nil); });
        }
    });
}

#pragma mark Записи

- (void)loadRecordsForDay:(NSDate *)day
               completion:(void (^)(NSArray *, NSString *))completion {
    NSString *dayString = YCDayFromDate(day);

    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(nil, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            NSMutableArray *found = [NSMutableArray array];

            /**
             * Один и тот же день в обе границы.
             *
             * У YClients start_date и end_date включающие, так что это
             * ровно одни сутки. Брать день с запасом соблазнительно —
             * тогда листание вперёд и назад шло бы без запроса, — но
             * запись, перетащенную на соседний день, пришлось бы искать
             * в двух списках сразу, и «куда она делась» стало бы обычным
             * вопросом.
             */
            CYCLIENTS_COUNTER count = cyclients_records([token UTF8String], company,
                                                        [dayString UTF8String],
                                                        [dayString UTF8String],
                                                        (__bridge void *)found,
                                                        YCCollectRecord);

            NSLog(@"[YClients/API] %@: записей %d, показываем %lu",
                  dayString, (int)count, (unsigned long)[found count]);

            /**
             * Ноль записей — это не ошибка: пустые дни бывают у всех.
             *
             * Отличить пустой день от неудавшегося запроса можно только по
             * пояснению транспорта: библиотека в обоих случаях возвращает 0.
             * Поэтому ошибкой считается лишь тот случай, когда сервер сам
             * что-то сказал.
             */
            NSString *message = YCTransportLastMessage();

            if ([found count] == 0 && [message length] > 0) {
                YCMain(^{ completion(nil, message); });
                return;
            }

            YCMain(^{ completion(found, nil); });
        }
    });
}

#pragma mark - Сборка запросов к записи

/**
 * Массив услуг для запроса: `[{"id":123},{"id":456}]`.
 *
 * Списком, а не одной услугой: у записи их может быть несколько, и все
 * запросы к PUT обязаны присылать набор целиком. Отправив одну вместо
 * трёх, мы бы стёрли две. Цену и скидку не передаём — сервер подставит те,
 * что заданы услуге в настройках филиала.
 */
static NSString *YCServicesJSON(NSArray *serviceIds) {
    NSMutableArray *services = [NSMutableArray array];

    for (NSNumber *identifier in serviceIds) {
        if ([identifier integerValue] > 0) {
            [services addObject:@{ @"id": identifier }];
        }
    }

    if ([services count] == 0) {
        return nil;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:services options:0 error:NULL];

    return data != nil ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                       : nil;
}

/** `{"name":"…","phone":"…"}` — сервер ждёт клиента одним объектом JSON. */
static NSString *YCClientJSON(NSString *name, NSString *phone, NSString *email) {
    NSMutableDictionary *client = [NSMutableDictionary dictionary];

    if ([name length] > 0) {
        [client setObject:name forKey:@"name"];
    }

    if ([phone length] > 0) {
        [client setObject:phone forKey:@"phone"];
    }

    if ([email length] > 0) {
        [client setObject:email forKey:@"email"];
    }

    if ([client count] == 0) {
        return nil;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:client options:0 error:NULL];

    return data != nil ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                       : nil;
}

/**
 * Вызов cyclients_record_set с заранее неизвестным набором полей.
 *
 * Функция принимает пары через `...`, а собрать список аргументов переменной
 * длины во время работы в C нельзя. Поэтому мест под пары написано десять,
 * а сколько из них прочтут, решает счётчик: va_arg зовётся ровно `count`
 * раз на пару, до остальных дело не доходит.
 *
 * Десяти хватает: самая полная замена — datetime, staff_id, seance_length,
 * client, services, comment, attendance, custom_color и save_if_busy —
 * это девять.
 */
static int YCRecordSet(const char *token, int company, int recordId, NSArray *pairs) {
    const char *k[10] = { NULL }, *v[10] = { NULL };

    NSUInteger count = [pairs count] / 2;

    if (count == 0) {
        return 0;
    }

    if (count > 10) {
        count = 10;
    }

    for (NSUInteger i = 0; i < count; i++) {
        k[i] = [[pairs objectAtIndex:i * 2] UTF8String];
        v[i] = [[pairs objectAtIndex:i * 2 + 1] UTF8String];
    }

    return cyclients_record_set(token, company, recordId, (int)count,
                                k[0], v[0], k[1], v[1], k[2], v[2], k[3], v[3], k[4], v[4],
                                k[5], v[5], k[6], v[6], k[7], v[7], k[8], v[8], k[9], v[9]);
}

static void YCAddPair(NSMutableArray *pairs, NSString *key, NSString *value) {
    if (value != nil) {
        [pairs addObject:key];
        [pairs addObject:value];
    }
}

/**
 * Запись целиком — основа любого PUT.
 *
 * PUT у этого сервера — замена, а не правка: на запрос из двух полей он
 * отвечает 422 и перечисляет всё, чего недостаёт. Поэтому каждое изменение
 * начинается с полного снимка записи, а сверху кладутся изменённые поля —
 * они в списке позже и потому побеждают при разборе на стороне библиотеки?
 * Нет: библиотека добавляет ключи в объект по порядку, а cJSON при
 * повторном ключе оставляет оба. Поэтому основа собирается уже с учётом
 * замен — см. аргументы.
 */
static NSMutableArray *YCBasePairs(YCRecord *record,
                                   NSDate *start,
                                   NSInteger staffId,
                                   NSTimeInterval length,
                                   NSString *comment,
                                   NSArray *serviceIds,
                                   NSString *clientJSON,
                                   NSInteger attendance) {
    NSMutableArray *pairs = [NSMutableArray array];

    YCAddPair(pairs, @"datetime", YCAPIFromDate(start ?: record.start));
    YCAddPair(pairs, @"staff_id",
              [NSString stringWithFormat:@"%d", (int)(staffId > 0 ? staffId : record.staffId)]);
    YCAddPair(pairs, @"seance_length",
              [NSString stringWithFormat:@"%d", (int)(length > 0 ? length : record.length)]);
    /**
     * client и services уходят **всегда**, пусть и пустыми.
     *
     * У записи, заведённой в веб-интерфейсе «без клиента» и без услуги,
     * обоих полей нет. Пропуск ключа сервер считает ошибкой — «Не передан
     * обязательный параметр client» — и перенос такой записи не проходил.
     * Пустой объект и пустой массив проходят проверку на присутствие
     * и означают ровно то, что есть: клиента нет, услуг нет.
     */
    YCAddPair(pairs, @"client",
              clientJSON
                  ?: YCClientJSON(record.clientName, YCDigits(record.clientPhone), nil)
                  ?: @"{}");
    YCAddPair(pairs, @"services", YCServicesJSON(serviceIds ?: record.serviceIds) ?: @"[]");
    YCAddPair(pairs, @"comment", comment ?: (record.comment ?: @""));
    YCAddPair(pairs, @"attendance", [NSString stringWithFormat:@"%d", (int)attendance]);

    return pairs;
}

/** Общее завершение для всех PUT: код, пояснение, блок на главном потоке. */
- (void)putRecord:(NSInteger)recordId
            pairs:(NSArray *)pairs
           action:(NSString *)action
         fallback:(NSString *)fallback
       completion:(void (^)(BOOL, NSString *))completion {
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(NO, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            int failed = YCRecordSet([token UTF8String], company, (int)recordId, pairs);

            if (failed == 0) {
                NSLog(@"[YClients/API] Запись %ld: %@", (long)recordId, action);

                YCMain(^{ completion(YES, nil); });
                return;
            }

            NSString *error = [self failureWithFallback:fallback];

            NSLog(@"[YClients/API] Запись %ld, %@ — отказ: %@",
                  (long)recordId, action, error);

            YCMain(^{ completion(NO, error); });
        }
    });
}

#pragma mark Создание и правка

- (void)createRecordForStaff:(NSInteger)staffId
                        name:(NSString *)name
                       phone:(NSString *)phone
                       start:(NSDate *)start
                      length:(NSTimeInterval)length
                     comment:(NSString *)comment
                   serviceId:(NSInteger)serviceId
                       color:(NSString *)color
                       force:(BOOL)force
                  completion:(void (^)(NSInteger, NSString *))completion {
    NSString *when = YCAPIFromDate(start);

    /**
     * Имя и телефон уходят строками, пустыми в том числе, но не nil.
     *
     * Библиотека проверяет их через assert, и пустая строка эту проверку
     * проходит: пустые имя **и** телефон означают «клиента нет вовсе» —
     * объект client тогда просто не кладётся в запрос, и сервер заводит
     * запись без клиента. Именно так и работает «Продолжить без клиента».
     *
     * А вот nil проверку не проходит: [nil UTF8String] возвращает NULL,
     * и приложение обрывается внутри assert, без сообщения и без следа
     * в журнале падений. Сейчас nil сюда не приходит ни от кого, но
     * держаться это может только на внимательности всех вызывающих —
     * а здесь достаточно одной строки.
     */
    NSString *safeName = name ?: @"";
    NSString *digits = YCDigits(phone);
    NSString *safeComment = comment ?: @"";
    NSString *services = YCServicesJSON(serviceId > 0 ? @[ @(serviceId) ] : nil);
    NSString *safeColor = color ?: @"";

    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(0, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            /**
             * Всё, кроме пяти штатных аргументов, уходит парами.
             *
             * services уходит всегда, пустым списком в том числе: ключ
             * должен быть, иначе сервер отвечает 422 «не передан
             * обязательный параметр». Цвет передаётся пустой строкой,
             * а не пропускается: пустой custom_color сервер понимает
             * как «без цвета».
             *
             * save_if_busy добавляется четвёртой парой только при force —
             * поэтому число пар и считается, а не стоит константой.
             */
            CYCLIENTS_ID recordId = force
                ? cyclients_record_new(
                    [token UTF8String], company, (int)staffId,
                    [safeName UTF8String], [digits UTF8String],
                    [when UTF8String], (int)length,
                    4,
                    "comment", [safeComment UTF8String],
                    "services", [(services ?: @"[]") UTF8String],
                    "custom_color", [safeColor UTF8String],
                    "save_if_busy", "1")
                : cyclients_record_new(
                    [token UTF8String], company, (int)staffId,
                    [safeName UTF8String], [digits UTF8String],
                    [when UTF8String], (int)length,
                    3,
                    "comment", [safeComment UTF8String],
                    "services", [(services ?: @"[]") UTF8String],
                    "custom_color", [safeColor UTF8String]);

            if (recordId > 0) {
                NSLog(@"[YClients/API] Создана запись %d на %@", (int)recordId, when);

                YCMain(^{ completion(recordId, nil); });
                return;
            }

            NSString *error = [self failureWithFallback:
                @"Запись не создана. Возможно, это время уже занято."];

            NSLog(@"[YClients/API] Запись не создана: %@", error);

            YCMain(^{ completion(0, error); });
        }
    });
}

- (void)updateRecord:(YCRecord *)record
                name:(NSString *)name
               phone:(NSString *)phone
               email:(NSString *)email
               staff:(NSInteger)staffId
               start:(NSDate *)start
              length:(NSTimeInterval)length
             comment:(NSString *)comment
          serviceIds:(NSArray *)serviceIds
               color:(NSString *)color
        detachClient:(BOOL)detachClient
          completion:(void (^)(BOOL, NSString *))completion {
    /**
     * Клиент пустым не отправляется.
     *
     * Сервер понял бы `{"name":""}` как «стереть имя», и поле, случайно
     * очищенное на экране правки, стёрло бы имя постоянного клиента
     * в базе филиала. Пустой клиент означает «оставить прежнего».
     */
    /**
     * Пустой объект вместо nil, когда клиента сняли нарочно.
     *
     * nil в YCBasePairs означает «возьми клиента из самой записи» —
     * защита от случайно очищенного поля. Здесь очистка не случайна,
     * и подставлять прежнего нельзя: «{}» пройдёт проверку сервера
     * на присутствие ключа и будет значить ровно то, что есть.
     */
    NSString *client = detachClient ? @"{}"
                                    : YCClientJSON(name, YCDigits(phone), email);

    NSMutableArray *pairs = YCBasePairs(record, start, staffId, length, comment ?: @"",
                                        serviceIds, client, record.attendance);

    YCAddPair(pairs, @"custom_color", color ?: @"");

    [self putRecord:record.recordId pairs:pairs action:@"изменена"
           fallback:@"Изменения не сохранены." completion:completion];
}

- (void)moveRecord:(YCRecord *)record
           toStart:(NSDate *)start
             staff:(NSInteger)staffId
        saveIfBusy:(BOOL)saveIfBusy
        completion:(void (^)(BOOL, NSString *))completion {
    /**
     * Перенос — та же замена целиком, но все поля, кроме времени
     * и сотрудника, берутся из самой записи: возвращаются серверу такими,
     * какими он их отдал. Испортить имя или комментарий перетаскиванием
     * нечем.
     */
    NSMutableArray *pairs = YCBasePairs(record, start, staffId, 0, nil, nil, nil,
                                        record.attendance);

    YCAddPair(pairs, @"custom_color", record.customColor ?: @"");

    if (saveIfBusy) {
        // Ключа save_if_busy не было в таблице полей библиотеки, и он молча
        // уходил в custom_fields — то есть в никуда. См. правку в structs.h.
        YCAddPair(pairs, @"save_if_busy", @"1");
    }

    [self putRecord:record.recordId pairs:pairs action:@"перенесена"
           fallback:@"Перенести не удалось." completion:completion];
}

- (void)setAttendance:(NSInteger)attendance
             ofRecord:(YCRecord *)record
           completion:(void (^)(BOOL, NSString *))completion {
    NSMutableArray *pairs = YCBasePairs(record, nil, 0, 0, nil, nil, nil, attendance);

    YCAddPair(pairs, @"custom_color", record.customColor ?: @"");

    [self putRecord:record.recordId pairs:pairs action:@"сменила статус"
           fallback:@"Статус не изменён." completion:completion];
}

- (void)deleteRecord:(YCRecord *)record
          completion:(void (^)(BOOL, NSString *))completion {
    NSInteger recordId = record.recordId;

    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(NO, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            int failed = cyclients_record_remove([token UTF8String], company, (int)recordId);

            if (failed == 0) {
                NSLog(@"[YClients/API] Запись %ld удалена", (long)recordId);

                YCMain(^{ completion(YES, nil); });
                return;
            }

            NSString *error = [self failureWithFallback:@"Удалить не удалось."];

            YCMain(^{ completion(NO, error); });
        }
    });
}

#pragma mark Расписание

/**
 * Что накапливает разбор расписания одного сотрудника.
 *
 * Библиотека зовёт обратный вызов на каждый день диапазона, а нам нужен
 * ровно один — тот, о котором спросили. Лишние дни приходить не должны,
 * но проверка стоит дёшево, а сетка, нарисованная по чужому дню, стоит
 * дорого.
 */
typedef struct {
    __unsafe_unretained NSMutableArray *slots;
    __unsafe_unretained NSString *wanted;
    BOOL answered;
} YCScheduleSink;

/** «10:00» и «10:00:00» — в минуты от полуночи. */
static NSInteger YCMinutesFromClock(const char *text) {
    int hours = 0, minutes = 0;

    if (text == NULL || sscanf(text, "%d:%d", &hours, &minutes) != 2) {
        return -1;
    }

    if (hours < 0 || hours > 24 || minutes < 0 || minutes > 59) {
        return -1;
    }

    return hours * 60 + minutes;
}

static int YCCollectSchedule(void *userdata, const char *date,
                             int nslots, const CYCSlot *slots) {
    @autoreleasepool {
        YCScheduleSink *sink = (YCScheduleSink *)userdata;
        NSString *day = YCStr(date);

        // Дата приходит как «2026-09-08», иногда с временем — сравниваем
        // по первым десяти знакам.
        if ([day length] >= 10) {
            day = [day substringToIndex:10];
        }

        if (![day isEqualToString:sink->wanted]) {
            return 0;
        }

        sink->answered = YES;

        for (int i = 0; i < nslots; i++) {
            NSInteger from = YCMinutesFromClock(slots[i].from);
            NSInteger to = YCMinutesFromClock(slots[i].to);

            /**
             * Полночь как конец интервала означает конец суток.
             *
             * Смена «с 20:00 до 00:00» приходит именно так, и взятое
             * буквально это интервал отрицательной длины — колонка
             * сотрудника оказалась бы целиком нерабочей.
             */
            if (to == 0 && from > 0) {
                to = 24 * 60;
            }

            if (from < 0 || to <= from) {
                continue;
            }

            [sink->slots addObject:[YCSlot slotFrom:from to:to]];
        }
    }

    return 0;
}

- (void)loadScheduleForDay:(NSDate *)day
                     staff:(NSArray *)staff
                completion:(void (^)(NSDictionary *, NSString *))completion {
    NSString *date = YCDayFromDate(day);
    NSArray *members = [staff copy];

    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(nil, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            NSMutableDictionary *result = [NSMutableDictionary dictionary];

            for (YCStaff *member in members) {
                @autoreleasepool {
                    NSMutableArray *slots = [NSMutableArray array];
                    YCScheduleSink sink;

                    sink.slots = slots;
                    sink.wanted = date;
                    sink.answered = NO;

                    cyclients_schedule([token UTF8String], company,
                                       (int)member.staffId,
                                       [date UTF8String], [date UTF8String],
                                       &sink, YCCollectSchedule);

                    // Сервер промолчал — значит про этот день мы ничего
                    // не знаем, и записывать «выходной» нельзя.
                    if (!sink.answered) {
                        continue;
                    }

                    [slots sortUsingComparator:^NSComparisonResult(YCSlot *a, YCSlot *b) {
                        if (a.from < b.from) return NSOrderedAscending;
                        if (a.from > b.from) return NSOrderedDescending;
                        return NSOrderedSame;
                    }];

                    YCScheduleDay *entry = [[YCScheduleDay alloc] init];

                    entry.staffId = member.staffId;
                    entry.date = date;
                    entry.slots = slots;

                    [result setObject:entry forKey:@(member.staffId)];
                }
            }

            /**
             * В журнал — не только сколько, но и что именно.
             *
             * «Сотрудников 2 из 2» не отвечает на единственный вопрос,
             * который задают, когда сетка выглядит не так: работает ли
             * человек по мнению сервера и с какого по какое.
             */
            for (YCStaff *member in members) {
                YCScheduleDay *entry = [result objectForKey:@(member.staffId)];

                if (entry == nil) {
                    NSLog(@"[YClients/Расписание] %@ (%ld): сервер не ответил",
                          member.name, (long)member.staffId);
                    continue;
                }

                NSMutableArray *shown = [NSMutableArray array];

                for (YCSlot *slot in entry.slots) {
                    [shown addObject:[NSString stringWithFormat:@"%@–%@",
                                      [slot fromText], [slot toText]]];
                }

                NSLog(@"[YClients/Расписание] %@ (%ld) на %@: %@",
                      member.name, (long)member.staffId, date,
                      [shown count] > 0 ? [shown componentsJoinedByString:@", "]
                                        : @"выходной");
            }

            NSLog(@"[YClients/API] Расписание на %@: сотрудников %lu из %lu",
                  date, (unsigned long)[result count], (unsigned long)[members count]);

            YCMain(^{ completion(result, nil); });
        }
    });
}

- (void)setSchedule:(NSArray *)slots
           forStaff:(NSInteger)staffId
              onDay:(NSDate *)day
         completion:(void (^)(BOOL, NSString *))completion {
    NSString *date = YCDayFromDate(day);
    NSArray *safeSlots = [slots copy] ?: @[];

    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(NO, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            NSUInteger count = MIN([safeSlots count], (NSUInteger)CYC_MAX_SLOTS);
            CYCSlot *raw = calloc(count > 0 ? count : 1, sizeof(CYCSlot));

            if (raw == NULL) {
                YCMain(^{ completion(NO, @"Не хватило памяти"); });
                return;
            }

            for (NSUInteger i = 0; i < count; i++) {
                YCSlot *slot = [safeSlots objectAtIndex:i];

                strncpy(raw[i].from, [[slot fromText] UTF8String], sizeof(raw[i].from) - 1);
                strncpy(raw[i].to, [[slot toText] UTF8String], sizeof(raw[i].to) - 1);
            }

            int rc = cyclients_schedule_set([token UTF8String], company,
                                            (int)staffId, [date UTF8String],
                                            (int)count, raw);

            free(raw);

            if (rc == 0) {
                NSLog(@"[YClients/API] Расписание сотрудника %ld на %@ записано, интервалов %lu",
                      (long)staffId, date, (unsigned long)count);

                YCMain(^{ completion(YES, nil); });
                return;
            }

            NSString *error = [self failureWithFallback:
                @"Расписание не сохранилось."];

            NSLog(@"[YClients/API] Расписание не записано: %@", error);

            YCMain(^{ completion(NO, error); });
        }
    });
}

#pragma mark Клиенты

/**
 * Клиент из пар ключ-значение, которые отдаёт cyclients_clients_search.
 *
 * Поиск возвращает не CYCClient, а плоскую таблицу полей — ровно тех,
 * что запросили. Здесь она перекладывается в объект; отсутствующее поле
 * остаётся пустым.
 */
/**
 * Что накапливает разбор клиентов между вызовами.
 *
 * Список клиентов в клинике — тысячи человек, и сервер отдаёт их
 * страницами по сотне. Ждать конца незачем: показывать надо по мере
 * прихода, а «показать всех» никому не нужно — нужен первый экран
 * и поиск.
 */
typedef struct {
    __unsafe_unretained NSMutableArray *found;
    __unsafe_unretained id partial;      // блок «вот ещё порция»
    NSInteger limit;                     // 0 — без предела
    NSInteger flushed;                   // сколько уже показано
} YCClientSink;

static int YCCollectClientFields(void *userdata, int nfields, const kvpair_t *fields) {
    @autoreleasepool {
        YCClientSink *sink = (YCClientSink *)userdata;
        YCClient *item = [[YCClient alloc] init];

        for (int i = 0; i < nfields; i++) {
            NSString *key = YCStr(fields[i].key);
            NSString *value = YCStr(fields[i].value);

            if ([key isEqualToString:@"id"]) {
                item.clientId = [value integerValue];
            } else if ([key isEqualToString:@"name"]) {
                item.name = value;
            } else if ([key isEqualToString:@"surname"]) {
                item.surname = value;
            } else if ([key isEqualToString:@"patronymic"]) {
                item.patronymic = value;
            } else if ([key isEqualToString:@"phone"]) {
                item.phone = value;
            } else if ([key isEqualToString:@"email"]) {
                item.email = value;
            }
        }

        [sink->found addObject:item];

        /**
         * Порция уходит на экран каждые полсотни.
         *
         * Копия, а не сам массив: он продолжает расти в фоновой очереди,
         * пока главный поток по нему ходит, а это верный способ получить
         * «изменён во время перебора».
         */
        if ((NSInteger)[sink->found count] - sink->flushed >= 50) {
            sink->flushed = (NSInteger)[sink->found count];

            if (sink->partial != nil) {
                NSArray *snapshot = [sink->found copy];
                void (^partial)(NSArray *) = sink->partial;

                YCMain(^{ partial(snapshot); });
            }
        }

        // Предел означает «дальше не листай»: библиотека прекращает
        // запрашивать страницы, как только обратный вызов скажет стоп.
        if (sink->limit > 0 && (NSInteger)[sink->found count] >= sink->limit) {
            return 1;
        }
    }

    return 0;
}

- (void)loadVisitsForClient:(NSInteger)clientId
                 completion:(void (^)(NSArray *, NSString *))completion {
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(nil, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            NSMutableArray *found = [NSMutableArray array];

            cyclients_client_visits([token UTF8String], company, (int)clientId,
                                    (__bridge void *)found, YCCollectRecord);

            /**
             * Свежие сверху.
             *
             * Сервер порядка не обещает, а нужен он вполне определённый:
             * первым делом смотрят, что было в прошлый раз, и лезть за этим
             * в конец списка — работа на пустом месте.
             */
            [found sortUsingComparator:^NSComparisonResult(YCRecord *a, YCRecord *b) {
                return [b.start compare:a.start];
            }];

            NSLog(@"[YClients/API] Записей у клиента %ld: %lu",
                  (long)clientId, (unsigned long)[found count]);

            NSString *message = YCTransportLastMessage();

            if ([found count] == 0 && [message length] > 0) {
                YCMain(^{ completion(nil, message); });
                return;
            }

            YCMain(^{ completion(found, nil); });
        }
    });
}

- (void)searchClients:(NSString *)query
              partial:(void (^)(NSArray *))partial
           completion:(void (^)(NSArray *, NSString *))completion {
    NSString *safeQuery = query ?: @"";

    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *token = nil;
            int company = 0;

            [self snapshotToken:&token company:&company];

            if ([token length] == 0 || company == 0) {
                YCMain(^{ completion(nil, @"Не выбран филиал"); });
                return;
            }

            YCTransportResetLastMessage();

            NSMutableArray *found = [NSMutableArray array];

            /**
             * Без запроса берём только первую сотню.
             *
             * Пустой поиск — это «покажи список», а не «выгрузи базу»:
             * листать тысячи карточек пальцем никто не станет, нужного
             * человека находят поиском. С запросом предела нет — там
             * совпадений единицы.
             */
            YCClientSink sink;

            sink.found = found;
            sink.partial = partial;
            sink.limit = [safeQuery length] > 0 ? 0 : 100;
            sink.flushed = 0;

            /**
             * Первое поле в списке становится полем сортировки.
             *
             * Сортируем по фамилии: в клинике клиента ищут по ней, а не
             * по имени. Фамилия и отчество запрашиваются отдельно — сервер
             * отдаёт ровно те поля, что перечислены, и без них в списке
             * оставались одни имена.
             */
            cyclients_clients_search([token UTF8String], company,
                                     "surname,name,patronymic,phone,email,id",
                                     [safeQuery UTF8String],
                                     &sink, YCCollectClientFields);

            NSLog(@"[YClients/API] Клиентов по «%@»: %lu",
                  safeQuery, (unsigned long)[found count]);

            NSString *message = YCTransportLastMessage();

            if ([found count] == 0 && [message length] > 0) {
                YCMain(^{ completion(nil, message); });
                return;
            }

            YCMain(^{ completion(found, nil); });
        }
    });
}

@end
