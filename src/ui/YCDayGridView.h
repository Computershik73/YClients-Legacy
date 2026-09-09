#import <UIKit/UIKit.h>

#import "YCModel.h"

@class YCDayGridView;

@protocol YCDayGridDelegate <NSObject>

/** Тап по пустому месту: завести запись у этого сотрудника на это время. */
- (void)grid:(YCDayGridView *)grid
    didTapEmptySlotForStaff:(YCStaff *)staff
                     atTime:(NSDate *)time;

/** Тап по записи: открыть её на правку. */
- (void)grid:(YCDayGridView *)grid didTapRecord:(YCRecord *)record;

/**
 * Запись отпустили в новом месте.
 *
 * Зовётся только если место действительно изменилось. Сетка к этому моменту
 * уже переставила прямоугольник — то есть показала предполагаемый исход,
 * не дожидаясь сервера. Если сервер откажет, вызывающий обязан позвать
 * -reloadRecords: и вернуть всё как было.
 */
- (void)grid:(YCDayGridView *)grid
    didMoveRecord:(YCRecord *)record
          toStaff:(YCStaff *)staff
             time:(NSDate *)time;

/**
 * Перетаскивание началось или кончилось.
 *
 * Нужно затем, что на время перетаскивания прокрутку надо выключить:
 * иначе палец, ведущий запись вниз, одновременно тянет и весь экран.
 */
- (void)grid:(YCDayGridView *)grid didChangeDragging:(BOOL)dragging;

@end


/**
 * Сетка одного дня: время по вертикали, сотрудники по колонкам.
 *
 * Сама по себе она не прокручивается и не рисует ни шкалу времени, ни шапку
 * с именами — это забота YCDayController, который кладёт её в UIScrollView
 * и подставляет шкалу и шапку плавающими видами. Здесь только поле сетки:
 * линии, записи и работа с пальцем.
 */
@interface YCDayGridView : UIView

@property (nonatomic, weak) id<YCDayGridDelegate> delegate;

/**
 * Прокрутка, в которой лежит сетка.
 *
 * Ссылка нужна ради одного: когда запись тащат к краю экрана, сетка должна
 * подкручивать содержимое сама. Рабочий день не помещается на экран целиком
 * ни на одном устройстве, и без этого перенести запись с утра на вечер
 * было бы нельзя вовсе — только через экран правки.
 */
@property (nonatomic, weak) UIScrollView *scrollView;

/** Показываемый день (полночь). */
@property (nonatomic, strong) NSDate *day;

/** Колонки: массив YCStaff. */
@property (nonatomic, copy) NSArray *staff;

/** Записи дня: массив YCRecord. Раскладываются по колонкам сами. */
@property (nonatomic, copy) NSArray *records;

/**
 * Приёмные часы: номер сотрудника (NSNumber) → YCScheduleDay.
 *
 * Нужны сетке, чтобы серым закрашивать нерабочее время каждой колонки
 * по отдельности, а не всем одинаково от звонка до звонка. У одного
 * мастера смена с восьми, у другого с двух, у третьего сегодня выходной —
 * общая серая полоса сверху и снизу не говорит ни о ком из них ничего.
 *
 * Пусто — сетка рисуется как раньше, по общим часам работы салона.
 */
@property (nonatomic, copy) NSDictionary *schedule;

/** Ширина одной колонки; считает контроллер, исходя из ширины экрана. */
@property (nonatomic, assign) CGFloat columnWidth;

/**
 * Границы показываемого времени, в часах от полуночи.
 *
 * Задаются не напрямую: сетка выводит их из рабочего дня салона и из самих
 * записей — запись в 7:30 расширит начало до семи. Читать их нужно затем,
 * что по ним же рисуется шкала времени, а она живёт снаружи.
 */
@property (nonatomic, readonly) NSInteger startHour;
@property (nonatomic, readonly) NSInteger endHour;

/** Размер, который сетка хочет занимать при текущих данных. */
- (CGSize)contentSize;

/** Координата Y для момента времени — по ней рисуется шкала. */
- (CGFloat)yForDate:(NSDate *)date;

/** Идёт ли сейчас перетаскивание. */
@property (nonatomic, readonly) BOOL isDragging;

@end
