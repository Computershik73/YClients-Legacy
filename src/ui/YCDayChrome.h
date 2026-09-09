#import <UIKit/UIKit.h>

/**
 * Обвязка сетки: шкала времени слева и шапка с именами сверху.
 *
 * Оба вида лежат внутри той же прокрутки, что и сетка, но не едут вместе
 * с ней целиком: шкала держится у левого края при прокрутке вбок, шапка —
 * у верхнего при прокрутке вниз. Делает это YCDayController, переставляя их
 * на каждом сдвиге; отдельного слоя или второй прокрутки для этого не нужно.
 *
 * Почему не UITableView с закреплёнными заголовками: она умеет закреплять
 * только по одной оси, а здесь нужно по обеим — и время, и имена должны
 * оставаться на виду.
 */

/** Часы по вертикали. */
@interface YCRulerView : UIView

@property (nonatomic, assign) NSInteger startHour;
@property (nonatomic, assign) NSInteger endHour;

@end


/** Имена сотрудников по горизонтали. */
@interface YCHeaderView : UIView

/** Массив YCStaff. */
@property (nonatomic, copy) NSArray *staff;

@property (nonatomic, assign) CGFloat columnWidth;

@end
