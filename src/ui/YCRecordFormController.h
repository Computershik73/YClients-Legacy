#import <UIKit/UIKit.h>

#import "YCFormScreen.h"
#import "YCModel.h"

@class YCRecordFormController;

@protocol YCRecordFormDelegate <NSObject>

/** Запись создана или изменена — день надо перечитать. */
- (void)recordFormDidChangeRecords:(YCRecordFormController *)form;

@end


/**
 * «Новая запись» и правка — форма по снимку оригинала: Клиент, Услуги,
 * Сотрудник, Дата и время, затем «Дополнительные настройки» — Длительность,
 * Цвет записи, Комментарий — и жёлтая кнопка внизу.
 *
 * Чего нет и почему: «Ресурсы» и «Категории» держатся на эндпойнтах,
 * которых в cYclients нет; строки ради строк здесь не рисуются.
 */
@interface YCRecordFormController : YCFormScreen

@property (nonatomic, weak) id<YCRecordFormDelegate> delegate;

/** Новая запись у сотрудника на время. */
- (id)initWithNewRecordForStaff:(YCStaff *)staff
                         atTime:(NSDate *)time
                          staff:(NSArray *)allStaff;

/** Правка существующей. */
- (id)initWithRecord:(YCRecord *)record staff:(NSArray *)allStaff;

/**
 * Подставляет клиента в новую запись.
 *
 * Зовётся сразу после создания формы, до её показа. Нужно экрану записей
 * клиента: там человек уже известен, и заставлять набирать его имя
 * и телефон заново — работа впустую.
 */
- (void)prefillClientName:(NSString *)name phone:(NSString *)phone;

@end
