#import <UIKit/UIKit.h>

/** Вкладка «Клиенты»: поиск по базе филиала и список имя/телефон. */
@interface YCClientsController : UITableViewController
@end


/**
 * Вкладка «Ещё»: профиль, филиал, сотрудники, услуги, настройки, выход.
 *
 * Аналитика, финансы, склад и остальное из оригинала — это либо другие
 * эндпойнты, либо просто ссылки на сайт; ни того ни другого у библиотеки
 * нет, и строк ради строк здесь не рисуется.
 */
@interface YCMoreController : UITableViewController
@end


/** Простой список «заголовок / подпись» — сотрудники, услуги. */
@interface YCListController : UITableViewController

- (id)initWithTitle:(NSString *)title rows:(NSArray *)rows;   // массив @[title, subtitle]

@end
