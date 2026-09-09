#import <UIKit/UIKit.h>

@class YCWeekStrip;

@protocol YCWeekStripDelegate <NSObject>
- (void)weekStrip:(YCWeekStrip *)strip didPickDay:(NSDate *)day;
@end

/**
 * Тёмная полоса недели внизу журнала: пн 31 · вт 1 · … · вс 6.
 *
 * Выбранный день — жёлтый квадрат, суббота и воскресенье — красным,
 * как в оригинале. Смахивание влево-вправо листает неделю; тап по дню
 * открывает его.
 */
@interface YCWeekStrip : UIView

@property (nonatomic, weak) id<YCWeekStripDelegate> delegate;

/** Выбранный день; полоса показывает его неделю. */
@property (nonatomic, strong) NSDate *day;

@end
