#import <UIKit/UIKit.h>

/** Что выбрали в шторке. */
typedef enum {
    YCDrawerItemJournal = 0,
    YCDrawerItemMonth,
    YCDrawerItemClients,
    YCDrawerItemAppearance,
    YCDrawerItemAbout,
    YCDrawerItemCompany,
    YCDrawerItemLogout,
    YCDrawerItemCount
} YCDrawerItem;

@class YCDrawerController;

@protocol YCDrawerDelegate <NSObject>
- (void)drawer:(YCDrawerController *)drawer didChooseItem:(YCDrawerItem)item;
@end

/**
 * Шторка слева вместо панели вкладок.
 *
 * Панель вкладок стоила сорока девяти точек внизу экрана — постоянно,
 * на каждом экране, ради трёх пунктов, между которыми переключаются
 * несколько раз за день. На четырёхдюймовом телефоне это восьмая часть
 * высоты, отданная навигации, тогда как работа идёт с записями, и им
 * места как раз не хватает.
 *
 * Шторка занимает ноль, пока её не открыли, и вмещает сколько угодно
 * пунктов — включая те, что раньше прятались во вкладке «Ещё» третьим
 * уровнем вложенности.
 *
 * Устроена нарочно просто: содержимое и панель — два вида-соседа,
 * открытие двигает кадр. Ни жестов протаскивания с краю, ни собственной
 * анимации переходов: и то и другое на iOS 6 пришлось бы писать с нуля,
 * а выгоды от них здесь никакой.
 */
@interface YCDrawerController : UIViewController

- (id)initWithContentController:(UIViewController *)content;

@property (nonatomic, weak) id<YCDrawerDelegate> drawerDelegate;

/** Что показано справа от шторки. Замена закрывает её. */
@property (nonatomic, strong) UIViewController *contentController;

- (void)openDrawer;
- (void)closeDrawer;
- (void)toggleDrawer;

/** Открыта ли — нужно экранам, чтобы не отвечать на нажатия под затемнением. */
@property (nonatomic, readonly) BOOL isOpen;

@end
