#import <Foundation/Foundation.h>

/**
 * Модель приложения.
 *
 * Обычные объекты Objective-C без единой строчки из cYclients — и это
 * намеренно. Библиотека отдаёт данные в статические структуры C, которые
 * действительны только внутри обратного вызова: следующая запись пишется
 * в ту же память поверх предыдущей. Сохранить такой указатель значит
 * получить список, где все записи одинаковы — последняя.
 *
 * Поэтому перекладывание в эти объекты происходит **внутри** обратного
 * вызова, в YCApi.m, и только там. Дальше по приложению ходят они,
 * а заголовки библиотеки не подключены больше нигде.
 */

/** Филиал. У одного логина их бывает несколько — тогда его спрашивают. */
@interface YCCompany : NSObject

@property (nonatomic, assign) NSInteger companyId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *city;

@end


/** Сотрудник — колонка в сетке дня. */
@interface YCStaff : NSObject

@property (nonatomic, assign) NSInteger staffId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *specialization;

/**
 * Длительность сеанса по умолчанию, секунды.
 *
 * Сервер держит её у сотрудника, и это разумное начальное значение для
 * новой записи: у мастера маникюра час, у администратора пятнадцать минут.
 * Ноль означает «сервер не сказал» — тогда берётся общий час.
 */
@property (nonatomic, assign) NSTimeInterval seanceLength;

@end


/**
 * Услуга филиала.
 *
 * Без неё запись не создаётся: сервер отвечает на POST /records отказом
 * «Не передан обязательный параметр services». Это не наша прихоть и не
 * поле «на всякий случай» — в YClients запись без услуги не существует,
 * потому что от услуги считаются и длительность, и стоимость.
 */
@interface YCService : NSObject

@property (nonatomic, assign) NSInteger serviceId;
@property (nonatomic, copy) NSString *title;

/** Длительность по умолчанию, секунды. 0 — сервер её не задал. */
@property (nonatomic, assign) NSTimeInterval duration;

/** Наименьшая цена; показывается рядом с названием при выборе. */
@property (nonatomic, assign) double price;

@end


/**
 * Склеивает фамилию, имя и отчество через пробел, пропуская пустые.
 *
 * Живёт снаружи класса, потому что нужна и записи: у неё клиент приходит
 * не объектом YCClient, а разложенным по полям, и собирать имя приходится
 * тем же способом, чтобы в сетке и в списке клиентов оно выглядело
 * одинаково.
 */
NSString *YCJoinName(NSString *surname, NSString *name, NSString *patronymic);

/** Клиент из базы филиала — то, что находит поиск. */
@interface YCClient : NSObject

@property (nonatomic, assign) NSInteger clientId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *surname;
@property (nonatomic, copy) NSString *patronymic;
@property (nonatomic, copy) NSString *phone;
@property (nonatomic, copy) NSString *email;

/**
 * Фамилия, имя и отчество одной строкой — то, что показывают везде.
 *
 * Порядок «Фамилия Имя Отчество», как в самом YClients и как принято
 * в медицинских карточках: по фамилии клиента и ищут. Пустые части
 * пропускаются, лишних пробелов не остаётся.
 */
@property (nonatomic, readonly) NSString *fullName;

@end


/**
 * Приёмные часы сотрудника на один день.
 *
 * Интервалов может быть несколько, и это не прихоть разметки: перерыв
 * в YClients не хранится отдельной сущностью, он и есть промежуток между
 * двумя интервалами. День с десяти до семи с обедом в два — это
 * 10:00–14:00 и 15:00–19:00, а не «день с перерывом».
 *
 * Пустой список интервалов означает выходной. Это ответ, а не отсутствие
 * ответа, и путать одно с другим нельзя: колонка сотрудника, который
 * сегодня не работает, приглашает записать к нему клиента, а сервер
 * такую запись отклонит.
 */
@interface YCSlot : NSObject

/** Начало и конец в минутах от полуночи. */
@property (nonatomic, assign) NSInteger from;
@property (nonatomic, assign) NSInteger to;

+ (id)slotFrom:(NSInteger)from to:(NSInteger)to;

/** «10:00» — как показывают и как отправляют обратно. */
- (NSString *)fromText;
- (NSString *)toText;

@end


/** Расписание одного сотрудника на один день. */
@interface YCScheduleDay : NSObject

@property (nonatomic, assign) NSInteger staffId;

/** Дата в виде «ГГГГ-ММ-ДД» — так её называет сервер. */
@property (nonatomic, copy) NSString *date;

/** Массив YCSlot по возрастанию времени. Пусто — выходной. */
@property (nonatomic, copy) NSArray *slots;

/** Работает ли сотрудник в этот день вообще. */
@property (nonatomic, readonly) BOOL isWorking;

/** Первое начало и последний конец, минуты. 0 и 0 у выходного. */
@property (nonatomic, readonly) NSInteger earliest;
@property (nonatomic, readonly) NSInteger latest;

/** Попадает ли минута дня внутрь приёмных часов. */
- (BOOL)coversMinute:(NSInteger)minute;

@end


/** Запись — прямоугольник в сетке дня. */
@interface YCRecord : NSObject

@property (nonatomic, assign) NSInteger recordId;
@property (nonatomic, assign) NSInteger staffId;

/** Начало записи в настенном времени салона — см. YCTime.h. */
@property (nonatomic, strong) NSDate *start;

/** Длительность в секундах. */
@property (nonatomic, assign) NSTimeInterval length;

@property (nonatomic, copy) NSString *clientName;
@property (nonatomic, copy) NSString *clientPhone;
@property (nonatomic, copy) NSString *clientEmail;
@property (nonatomic, assign) NSInteger clientId;
@property (nonatomic, copy) NSString *comment;

/** Названия услуг через запятую — показываются второй строкой на записи. */
@property (nonatomic, copy) NSString *services;

/**
 * Номера этих услуг — массив NSNumber.
 *
 * Нужны экрану правки, чтобы показать выбранной ту услугу, что уже стоит
 * в записи. По названию искать нельзя: названия повторяются, а менять
 * услугу записи по совпадению строк — верный способ подменить не ту.
 */
@property (nonatomic, copy) NSArray *serviceIds;

/**
 * Посещаемость: 2 — подтверждена, 1 — пришёл, 0 — ждём, -1 — не пришёл.
 * От неё зависит цвет записи в сетке.
 */
@property (nonatomic, assign) NSInteger attendance;

/** Цвет, назначенный записи в веб-интерфейсе; пустая строка, если не задан. */
@property (nonatomic, copy) NSString *customColor;

/** Конец записи; start плюс длительность. */
@property (nonatomic, readonly) NSDate *end;

/**
 * Что писать на прямоугольнике первой строкой.
 *
 * Имя клиента, а если его нет — телефон, а если нет и его — «Без имени».
 * Пустой прямоугольник в сетке неотличим от ошибки отрисовки, поэтому
 * какая-то подпись должна быть всегда.
 */
@property (nonatomic, readonly) NSString *title;

@end
