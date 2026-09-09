#import <UIKit/UIKit.h>

#import "YCModel.h"
#import "YCRecordFormController.h"

/**
 * Карточка записи — по снимку оригинала: переключатель посещаемости,
 * клиент, сотрудник со временем и карандашом, услуги, комментарий,
 * корзина в панели.
 *
 * «Товары и абонементы» и «К оплате» держатся на продажах, которых в API
 * библиотеки нет, — их здесь нет тоже.
 */
@interface YCRecordDetailController : UITableViewController

@property (nonatomic, weak) id<YCRecordFormDelegate> delegate;

- (id)initWithRecord:(YCRecord *)record staff:(NSArray *)allStaff;

@end
