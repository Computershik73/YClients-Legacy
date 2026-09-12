#import <Foundation/Foundation.h>

#import "YCModel.h"

/**
 * Единственная дверь к cYclients.
 *
 * Библиотека синхронная и не рассчитана на несколько потоков: почти каждый
 * её вызов складывает результат в статическую структуру и отдаёт указатель
 * на неё. Поэтому здесь всё выстроено в один ряд: одна последовательная
 * очередь, перекладывание в объекты модели внутри обратного вызова, блок
 * завершения — с главного потока.
 *
 * Ошибка отдаётся строкой, готовой к показу человеку. Nil означает успех.
 */

/** Вышли из учётной записи — надо показать экран входа. */
extern NSString *const YCDidLogOutNotification;

/** Просят сменить филиал — токен при этом остаётся. */
extern NSString *const YCShouldChooseCompanyNotification;


@interface YCApi : NSObject

+ (YCApi *)shared;

#pragma mark Состояние

@property (nonatomic, readonly) BOOL isAuthorized;
@property (nonatomic, readonly, copy) NSString *userName;
@property (nonatomic, readonly) NSInteger companyId;
@property (nonatomic, readonly, copy) NSString *companyTitle;

#pragma mark Вход

/**
 * Вход по логину и паролю. Пароль не сохраняется — только выданный токен.
 * Второй фактор не поддержан: если сервер его потребует, вернётся понятный
 * отказ.
 */
- (void)loginWithLogin:(NSString *)login
              password:(NSString *)password
            completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)logout;

#pragma mark Филиалы и сотрудники

/** Филиалы, доступные вошедшему. Массив YCCompany. */
- (void)loadCompaniesWithCompletion:(void (^)(NSArray *companies, NSString *error))completion;

- (void)selectCompany:(YCCompany *)company;

/** Сотрудники филиала без уволенных и скрытых. Массив YCStaff. */
- (void)loadStaffWithCompletion:(void (^)(NSArray *staff, NSString *error))completion;

/**
 * Услуги, которые оказывает этот сотрудник. Массив YCService, по алфавиту.
 *
 * Именно по сотруднику: услуга из каталога, не назначенная мастеру, даёт
 * 400 «Сотрудник не оказывает выбранные услуги». У сотрудника без услуг
 * возвращается ошибка, а не каталог. staffId == 0 — каталог филиала целиком.
 */
- (void)loadServicesForStaff:(NSInteger)staffId
                  completion:(void (^)(NSArray *services, NSString *error))completion;

#pragma mark Расписание

/**
 * Приёмные часы всех сотрудников на один день.
 *
 * Ключи словаря — номера сотрудников в NSNumber, значения — YCScheduleDay.
 * Сотрудник, которого в словаре нет, ответа от сервера не получил;
 * сотрудник с пустым списком интервалов — не работает. Различать это
 * важно: в первом случае колонку прячут по ошибке, во втором — по делу.
 *
 * Сервер отвечает на одного сотрудника за запрос, поэтому запросов
 * ровно столько, сколько сотрудников. Они идут по очереди в фоновой
 * очереди, и результат приходит один раз, когда собраны все: показывать
 * сетку, у которой колонки появляются по одной, хуже, чем показать её
 * на полсекунды позже.
 */
- (void)loadScheduleForDay:(NSDate *)day
                     staff:(NSArray *)staff
                completion:(void (^)(NSDictionary *schedule, NSString *error))completion;

/**
 * Заменяет расписание сотрудника на день целиком.
 *
 * Именно заменяет: то, что стояло в этот день, пропадает. Пустой массив
 * интервалов — это способ сделать день выходным, а не ошибка вызова.
 */
- (void)setSchedule:(NSArray *)slots
           forStaff:(NSInteger)staffId
              onDay:(NSDate *)day
         completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark Клиенты

/**
 * Клиенты филиала по строке поиска. Массив YCClient.
 *
 * partial зовётся по мере прихода страниц, каждые полсотни человек,
 * и получает всё найденное на этот момент: список наполняется на глазах,
 * а не появляется через полминуты целиком. Может не позваться ни разу —
 * если всё пришло одной страницей.
 *
 * Пустой запрос означает «покажи начало списка», и берётся только первая
 * сотня: в клинике клиентов тысячи, листать их пальцем никто не станет,
 * нужного находят поиском. С непустым запросом предела нет.
 */
- (void)searchClients:(NSString *)query
              partial:(void (^)(NSArray *clients))partial
           completion:(void (^)(NSArray *clients, NSString *error))completion;

/**
 * Все записи одного клиента — от первой до последней.
 *
 * Ради этого экрана: звонит человек, и надо за секунду вспомнить, что ему
 * делали в прошлый раз, прежде чем записывать снова. Сервер отдаёт их
 * одним запросом по /clients/visits/search и в порядке, который выбирает
 * сам, — здесь они переворачиваются свежими вверх.
 */
- (void)loadVisitsForClient:(NSInteger)clientId
                 completion:(void (^)(NSArray *records, NSString *error))completion;

#pragma mark Записи

/** Записи одного дня. Массив YCRecord. */
- (void)loadRecordsForDay:(NSDate *)day
               completion:(void (^)(NSArray *records, NSString *error))completion;

/**
 * Новая запись. Возвращает её номер, 0 при отказе.
 *
 * serviceId — 0 означает «без услуги»; сервер такую запись может и не
 * принять, но решать это ему, а не нам. color — hex без решётки или пустая
 * строка. Почта клиента при создании не передаётся: библиотека собирает
 * объект client сама из имени и телефона.
 *
 * force ставит save_if_busy: сервер перестаёт проверять, свободно ли
 * время. Нужно ровно для того случая, когда расписание на день ещё
 * не выставлено, а записать человека надо сейчас.
 */
- (void)createRecordForStaff:(NSInteger)staffId
                        name:(NSString *)name
                       phone:(NSString *)phone
                       start:(NSDate *)start
                      length:(NSTimeInterval)length
                     comment:(NSString *)comment
                   serviceId:(NSInteger)serviceId
                       color:(NSString *)color
                       force:(BOOL)force
                  completion:(void (^)(NSInteger recordId, NSString *error))completion;

/**
 * Правка записи. PUT у сервера — замена целиком, поэтому уходит всё.
 *
 * Пустые имя и телефон означают «оставить прежнего клиента», а не
 * «стереть»: поле, случайно очищенное на экране правки, иначе стёрло бы
 * имя постоянного клиента в базе салона.
 *
 * detachClient — тот случай, когда стереть хотели: в списке выбрали
 * «Без клиента». Тогда прежний не подставляется и уходит пустой объект.
 * Без этого флага снять клиента с записи было нельзя вовсе — очистка
 * полей молча возвращала того же человека.
 *
 * serviceIds — весь список услуг записи; если выбор не меняли, сюда идут
 * прежние. color — hex или пустая строка («без цвета»).
 */
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
          completion:(void (^)(BOOL ok, NSString *error))completion;

/**
 * Перенос — то, что делает перетаскивание. Все поля, кроме времени
 * и сотрудника, берутся из записи. saveIfBusy разрешает наложение.
 */
- (void)moveRecord:(YCRecord *)record
           toStart:(NSDate *)start
             staff:(NSInteger)staffId
        saveIfBusy:(BOOL)saveIfBusy
        completion:(void (^)(BOOL ok, NSString *error))completion;

/** Посещаемость: 0 — ожидание, 1 — пришёл, −1 — не пришёл, 2 — подтвердил. */
- (void)setAttendance:(NSInteger)attendance
             ofRecord:(YCRecord *)record
           completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteRecord:(YCRecord *)record
          completion:(void (^)(BOOL ok, NSString *error))completion;

@end
