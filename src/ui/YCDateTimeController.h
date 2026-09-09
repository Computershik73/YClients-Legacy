#import <UIKit/UIKit.h>

/**
 * «Дата и время»: календарь на несколько месяцев сверху, список времени
 * с шагом в пять минут снизу, жёлтая кнопка «Сохранить».
 *
 * Календарь свой, а не UIDatePicker: в оригинале сетка месяца, и колесо
 * выглядело бы чужим. Ничего сложного в ней нет — семь колонок кнопок.
 */
@interface YCDateTimeController : UIViewController

- (id)initWithDate:(NSDate *)date onChoose:(void (^)(NSDate *chosen))onChoose;

@end
