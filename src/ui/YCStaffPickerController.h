#import <UIKit/UIKit.h>

#import "YCFormScreen.h"
#import "YCModel.h"

/**
 * Выбор сотрудника — список с кружками и галочкой, «Сбросить» и «Сохранить».
 *
 * Блок зовётся при «Сохранить» с выбранным сотрудником (nil — сброшено).
 */
@interface YCStaffPickerController : YCFormScreen

- (id)initWithStaff:(NSArray *)staff
           selected:(NSInteger)staffId
           onChoose:(void (^)(YCStaff *staff))onChoose;

@end


/**
 * Выбор услуги — список услуг сотрудника с ценой; пустой список говорит
 * «Сотрудник не оказывает услуг», как в оригинале.
 */
@interface YCServicePickerController : YCFormScreen

- (id)initWithServices:(NSArray *)services
              selected:(NSInteger)serviceId
              onChoose:(void (^)(YCService *service))onChoose;

@end
