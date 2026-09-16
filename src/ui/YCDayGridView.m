#import "YCDayGridView.h"

#import <QuartzCore/QuartzCore.h>

#import "YCRecordView.h"
#import "YCTheme.h"
#import "YCTime.h"

/**
 * Рабочий день по умолчанию.
 *
 * Расписание филиала сервер отдаёт отдельным запросом и в виде, который
 * ещё надо разбирать по дням недели; вместо этого здесь взята рамка,
 * покрывающая почти любой график, а всё, что вне её, показывается серым.
 * Запись, назначенная на семь утра, границу раздвинет — то есть ошибка
 * рамки не может ничего спрятать.
 */
static const NSInteger YCWorkStartHour = 8;
static const NSInteger YCWorkEndHour = 22;

/** На сколько подкручивать за кадр, когда запись поднесли к краю. */
static const CGFloat YCAutoScrollStep = 6.0;

/** Ширина полосы у края, в которой начинается подкрутка. */
static const CGFloat YCAutoScrollMargin = 64.0;

/**
 * Объявлено заранее: -didMoveToWindow зовёт это раньше по файлу, чем оно
 * определено, и без объявления компилятор такой вызов не пропустит.
 */
@interface YCDayGridView ()
- (void)endDragCancelled:(BOOL)cancelled;
@end

@implementation YCDayGridView {
    NSMutableArray *_recordViews;

    NSInteger _startHour;
    NSInteger _endHour;

    // Перетаскивание
    YCRecordView *_dragged;
    CGPoint _grabOffset;      // где внутри записи взялся палец
    CGPoint _touchInWindow;   // последнее положение пальца, в окне
    CADisplayLink *_autoScroll;
    CGFloat _autoScrollDirection;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self != nil) {
        self.backgroundColor = [YCTheme gridPaper];
        self.contentMode = UIViewContentModeRedraw;

        _recordViews = [NSMutableArray array];
        _startHour = YCWorkStartHour;
        _endHour = YCWorkEndHour;
        _columnWidth = [YCTheme minColumnWidth];

        /**
         * Тап — один на всю сетку, а не по распознавателю на каждой записи.
         *
         * Куда он пришёлся, решает -recordViewAtPoint: по прямоугольникам.
         * Распознаватель на каждой записи пришлось бы заводить и убирать
         * при каждой перезагрузке дня, а различать «по записи» и «мимо»
         * всё равно понадобилось бы — записи не покрывают колонку целиком.
         */
        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];

        [self addGestureRecognizer:tap];

        /**
         * Долгое нажатие, а не сразу перетаскивание.
         *
         * Сетка живёт в прокрутке, и обычное движение пальца по ней —
         * это листание дня. Если бы запись бралась немедленно, пролистать
         * день, начав движение с записи, стало бы невозможно, а записи
         * занимают большую часть площади.
         *
         * Треть секунды — заметно меньше, чем принято у списков (там
         * полсекунды), и это намеренно: перенос записи здесь не редкое
         * действие, а одно из двух основных.
         */
        UILongPressGestureRecognizer *press =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(handleLongPress:)];

        press.minimumPressDuration = 0.35;

        // Палец на записи всегда чуть ползёт, пока ждёт срабатывания.
        // Без запаса перетаскивание не начиналось бы у половины попыток.
        press.allowableMovement = 12.0;

        [self addGestureRecognizer:press];
    }

    return self;
}

- (void)dealloc {
    [_autoScroll invalidate];
}

/**
 * Уход с экрана прерывает перетаскивание.
 *
 * CADisplayLink удерживает свою цель, пока не остановлен, — то есть сетка,
 * снятая с экрана посреди перетаскивания, не была бы освобождена вовсе,
 * а подкрутка продолжала бы работать в пустоту. Случай не выдуманный:
 * перетаскивание прерывает входящий звонок, а отменяющее событие приходит
 * не всегда.
 */
- (void)didMoveToWindow {
    [super didMoveToWindow];

    if (self.window == nil && _dragged != nil) {
        [self endDragCancelled:YES];
    }
}

#pragma mark Данные

- (void)setStaff:(NSArray *)staff {
    _staff = [staff copy];
    [self rebuild];
}

- (void)setSchedule:(NSDictionary *)schedule {
    _schedule = [schedule copy];
    [self setNeedsDisplay];
}

- (void)setRecords:(NSArray *)records {
    _records = [records copy];
    [self rebuild];
}

- (void)setDay:(NSDate *)day {
    _day = day;
    [self setNeedsDisplay];
}

- (void)setColumnWidth:(CGFloat)columnWidth {
    _columnWidth = columnWidth;
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (NSInteger)startHour { return _startHour; }
- (NSInteger)endHour { return _endHour; }
- (BOOL)isDragging { return _dragged != nil; }

/**
 * Пересобирает виды записей и заново считает границы времени.
 *
 * Виды создаются заново на каждую перезагрузку дня, а не переиспользуются:
 * записей в дне десятки, а не тысячи, и пул переработки здесь стоил бы
 * больше сложности, чем экономил работы.
 */
- (void)rebuild {
    // Перетаскиваемый вид пересобирать нельзя — он сейчас в руке.
    if (_dragged != nil) {
        return;
    }

    for (YCRecordView *view in _recordViews) {
        [view removeFromSuperview];
    }

    [_recordViews removeAllObjects];

    [self recomputeHours];

    for (YCRecord *record in self.records) {
        // Запись сотрудника, которого нет в колонках (уволен, скрыт),
        // рисовать негде. В журнал — чтобы «пропала запись» имело объяснение.
        if ([self columnIndexForStaffId:record.staffId] == NSNotFound) {
            NSLog(@"[YClients/Календарь] Запись %ld у сотрудника %ld вне колонок",
                  (long)record.recordId, (long)record.staffId);
            continue;
        }

        YCRecordView *view = [[YCRecordView alloc] initWithFrame:CGRectZero];

        view.record = record;

        [self addSubview:view];
        [_recordViews addObject:view];
    }

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

/**
 * Границы показываемого времени.
 *
 * Рабочий день плюс всё, что за него выходит. Запись, назначенная на семь
 * утра, обязана быть видна — иначе она молча исчезает из сетки, а вместе
 * с ней и занятое время.
 */
- (void)recomputeHours {
    _startHour = YCWorkStartHour;
    _endHour = YCWorkEndHour;

    for (YCRecord *record in self.records) {
        NSInteger begins = (NSInteger)floor(YCSecondsIntoDay(record.start) / 3600.0);
        NSInteger ends = (NSInteger)ceil(YCSecondsIntoDay(record.end) / 3600.0);

        if (begins < _startHour) {
            _startHour = MAX(0, begins);
        }

        // Запись, переходящая за полночь, обрезается сутками: рисовать
        // её в следующем дне сетка одного дня всё равно не умеет.
        if (ends > _endHour) {
            _endHour = MIN(24, ends);
        }
    }

    if (_endHour <= _startHour) {
        _endHour = _startHour + 1;
    }
}

#pragma mark Геометрия

- (CGSize)contentSize {
    return CGSizeMake([self.staff count] * self.columnWidth,
                      (_endHour - _startHour) * [YCTheme hourHeight]);
}

- (CGFloat)yForDate:(NSDate *)date {
    NSTimeInterval seconds = YCSecondsIntoDay(date) - _startHour * 3600.0;

    return (CGFloat)(seconds / 3600.0) * [YCTheme hourHeight];
}

/** Момент времени по координате Y, притянутый к шагу сетки. */
- (NSDate *)dateForY:(CGFloat)y {
    NSTimeInterval step = [YCTheme timeStep];
    NSTimeInterval seconds = _startHour * 3600.0 + (y / [YCTheme hourHeight]) * 3600.0;

    // Округление к ближайшему шагу, а не отбрасывание: иначе запись всегда
    // уезжала бы назад во времени, и перенести её на 10:00 с 9:58 было бы
    // нельзя — она вставала бы на 9:45.
    NSTimeInterval snapped = round(seconds / step) * step;

    if (snapped < 0) {
        snapped = 0;
    }

    // Начаться позже 23:59 запись не может — за сутками сетка кончается.
    if (snapped > 24 * 3600.0 - step) {
        snapped = 24 * 3600.0 - step;
    }

    return YCDateWithSecondsIntoDay(self.day, snapped);
}

- (NSInteger)columnIndexForX:(CGFloat)x {
    if ([self.staff count] == 0 || self.columnWidth <= 0) {
        return NSNotFound;
    }

    NSInteger index = (NSInteger)floor(x / self.columnWidth);

    if (index < 0) {
        index = 0;
    }

    if (index >= (NSInteger)[self.staff count]) {
        index = [self.staff count] - 1;
    }

    return index;
}

- (NSInteger)columnIndexForStaffId:(NSInteger)staffId {
    for (NSUInteger i = 0; i < [self.staff count]; i++) {
        YCStaff *member = [self.staff objectAtIndex:i];

        if (member.staffId == staffId) {
            return i;
        }
    }

    return NSNotFound;
}

- (CGRect)frameForRecord:(YCRecord *)record {
    NSInteger column = [self columnIndexForStaffId:record.staffId];

    if (column == NSNotFound) {
        return CGRectZero;
    }

    CGFloat top = [self yForDate:record.start];
    CGFloat height = (CGFloat)(record.length / 3600.0) * [YCTheme hourHeight];

    /**
     * Минимальная высота — иначе в запись не попасть пальцем.
     *
     * Пятиминутная запись это 5 точек; палец накрывает сорок. Рисовать её
     * честной высотой значило бы сделать её недоступной для нажатия,
     * а вместе с этим — невидимой.
     */
    if (height < 24.0) {
        height = 24.0;
    }

    // Полточки зазора справа: соседние записи не должны сливаться в полосу.
    return CGRectMake(column * self.columnWidth + 1.0, top,
                      self.columnWidth - 3.0, height);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    for (YCRecordView *view in _recordViews) {
        // Поднятую запись ведёт палец, а не раскладка.
        if (view == _dragged) {
            continue;
        }

        view.frame = [self frameForRecord:view.record];
    }
}

#pragma mark Отрисовка

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGFloat hourHeight = [YCTheme hourHeight];
    CGFloat width = [self.staff count] * self.columnWidth;

    [self shadeClosedHoursInContext:context width:width hourHeight:hourHeight];

    CGContextSetLineWidth(context, 1.0 / [UIScreen mainScreen].scale);

    // Получасовые линии — бледные. Рисуются первыми, чтобы часовые легли
    // поверх них там, где линии совпадают.
    CGContextSetStrokeColorWithColor(context, [YCTheme gridLineFaint].CGColor);
    CGContextBeginPath(context);

    for (NSInteger hour = _startHour; hour < _endHour; hour++) {
        CGFloat y = (hour - _startHour) * hourHeight + hourHeight / 2.0;

        CGContextMoveToPoint(context, 0, y);
        CGContextAddLineToPoint(context, width, y);
    }

    CGContextStrokePath(context);

    // Часовые линии и границы колонок.
    CGContextSetStrokeColorWithColor(context, [YCTheme gridLine].CGColor);
    CGContextBeginPath(context);

    for (NSInteger hour = _startHour; hour <= _endHour; hour++) {
        CGFloat y = (hour - _startHour) * hourHeight;

        CGContextMoveToPoint(context, 0, y);
        CGContextAddLineToPoint(context, width, y);
    }

    for (NSUInteger column = 1; column <= [self.staff count]; column++) {
        CGFloat x = column * self.columnWidth;

        CGContextMoveToPoint(context, x, 0);
        CGContextAddLineToPoint(context, x, [self contentSize].height);
    }

    CGContextStrokePath(context);

    [self engraveGridInContext:context width:width hourHeight:hourHeight];

    [self drawNowLineInContext:context width:width];
}

/**
 * Серым — то время, когда сотрудник не принимает.
 *
 * По колонкам, а не полосой во всю ширину. Раньше серым закрашивалось
 * всё до восьми утра и после восьми вечера — одинаково для всех, потому
 * что других сведений и не было. Толку от этого немного: смены у сотрудников
 * разные, и белое поле в колонке ничего не обещало.
 *
 * Теперь белое в колонке значит «сюда можно записать», а серое — «нельзя»,
 * и промежуток между интервалами — обеденный перерыв — виден так же ясно,
 * как утро и вечер.
 *
 * Пока расписание не пришло, остаётся прежнее поведение: общие часы
 * работы филиала. Показывать всё белым было бы обещанием, которого никто
 * не давал.
 */
- (void)shadeClosedHoursInContext:(CGContextRef)context
                            width:(CGFloat)width
                       hourHeight:(CGFloat)hourHeight {
    CGContextSetFillColorWithColor(context, [YCTheme closedHours].CGColor);

    if ([self.schedule count] == 0) {
        if (_startHour < YCWorkStartHour) {
            CGFloat until = (YCWorkStartHour - _startHour) * hourHeight;
            CGContextFillRect(context, CGRectMake(0, 0, width, until));
        }

        if (_endHour > YCWorkEndHour) {
            CGFloat from = (YCWorkEndHour - _startHour) * hourHeight;
            CGContextFillRect(context, CGRectMake(0, from, width,
                                                  (_endHour - YCWorkEndHour) * hourHeight));
        }

        return;
    }

    CGFloat minute = hourHeight / 60.0;

    for (NSUInteger column = 0; column < [self.staff count]; column++) {
        YCStaff *member = [self.staff objectAtIndex:column];
        YCScheduleDay *day = [self.schedule objectForKey:@(member.staffId)];
        CGFloat x = column * self.columnWidth;

        /**
         * Про кого сервер промолчал — того не закрашиваем вовсе.
         *
         * Серая колонка означает «не работает», и говорить это про
         * сотрудника, о котором ничего не известно, нельзя: расписание
         * могло просто не загрузиться.
         */
        if (day == nil) {
            continue;
        }

        if (!day.isWorking) {
            CGContextFillRect(context, CGRectMake(x, 0, self.columnWidth,
                                                  (_endHour - _startHour) * hourHeight));
            continue;
        }

        // Закрашивается всё, кроме интервалов: идём сверху вниз и
        // заливаем промежутки между ними, включая утро и вечер.
        CGFloat cursor = _startHour * 60.0;

        for (YCSlot *slot in day.slots) {
            if (slot.from > cursor) {
                CGContextFillRect(context,
                    CGRectMake(x, (cursor - _startHour * 60.0) * minute,
                               self.columnWidth, (slot.from - cursor) * minute));
            }

            cursor = MAX(cursor, (CGFloat)slot.to);
        }

        CGFloat end = _endHour * 60.0;

        if (cursor < end) {
            CGContextFillRect(context,
                CGRectMake(x, (cursor - _startHour * 60.0) * minute,
                           self.columnWidth, (end - cursor) * minute));
        }
    }
}

/**
 * Светлая грань под каждой линией — линии выглядят продавленными.
 *
 * Это тот же приём, что и у значков, только в сетке он важнее: одна серая
 * ниточка на белом читается как нарисованная поверх листа, а пара
 * «тёмная сверху, светлая снизу» — как бороздка в самом листе. Именно
 * так были расчерчены все таблицы и календари до iOS 7.
 *
 * На iOS 7 и новее не делается ничего: там линия и должна быть линией.
 */
- (void)engraveGridInContext:(CGContextRef)context
                       width:(CGFloat)width
                  hourHeight:(CGFloat)hourHeight {
    if (![YCTheme isLegacy]) {
        return;
    }

    // В тёмной теме грань едва заметна: на чёрном белая ниточка была бы
    // ярче самой линии, и бороздка вывернулась бы наизнанку.
    CGContextSetStrokeColorWithColor(context,
        [UIColor colorWithWhite:1.0 alpha:([YCTheme isDark] ? 0.10 : 0.9)].CGColor);

    CGContextBeginPath(context);

    for (NSInteger hour = _startHour; hour <= _endHour; hour++) {
        CGFloat y = (hour - _startHour) * hourHeight + 1.0;

        CGContextMoveToPoint(context, 0, y);
        CGContextAddLineToPoint(context, width, y);
    }

    for (NSUInteger column = 1; column <= [self.staff count]; column++) {
        CGFloat x = column * self.columnWidth + 1.0;

        CGContextMoveToPoint(context, x, 0);
        CGContextAddLineToPoint(context, x, [self contentSize].height);
    }

    CGContextStrokePath(context);
}

/** Полоса «сейчас» — только если показан сегодняшний день. */
- (void)drawNowLineInContext:(CGContextRef)context width:(CGFloat)width {
    NSDate *now = [NSDate date];

    /**
     * Сегодня определяется по настенному времени филиала.
     *
     * [NSDate date] — это момент, и чтобы получить из него настенные часы,
     * его надо пропустить через тот же приём, что и всё остальное время
     * в приложении: разобрать в местном поясе устройства и собрать заново
     * в поясе приложения. Иначе полоса встанет со сдвигом на часовой пояс,
     * а это единственное место, где сегодняшнее время берётся не с сервера.
     */
    NSDateFormatter *local = [[NSDateFormatter alloc] init];

    local.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    local.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    NSDate *wall = YCDateFromAPI([local stringFromDate:now]);

    if (wall == nil || !YCSameDay(wall, self.day)) {
        return;
    }

    CGFloat y = [self yForDate:wall];

    if (y < 0 || y > [self contentSize].height) {
        return;
    }

    CGContextSetStrokeColorWithColor(context, [YCTheme nowLine].CGColor);
    CGContextSetLineWidth(context, 1.0);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, 0, y);
    CGContextAddLineToPoint(context, width, y);
    CGContextStrokePath(context);

    // Кружок у левого края — чтобы полосу не спутать с часовой линией.
    CGContextSetFillColorWithColor(context, [YCTheme nowLine].CGColor);
    CGContextFillEllipseInRect(context, CGRectMake(-3.0, y - 3.0, 6.0, 6.0));
}

#pragma mark Палец

/** Вид записи под точкой, если он там есть. */
- (YCRecordView *)recordViewAtPoint:(CGPoint)point {
    // С конца: последние добавленные лежат выше, и попадать надо в верхний.
    for (NSInteger i = [_recordViews count] - 1; i >= 0; i--) {
        YCRecordView *view = [_recordViews objectAtIndex:i];

        if (CGRectContainsPoint(view.frame, point)) {
            return view;
        }
    }

    return nil;
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    CGPoint point = [tap locationInView:self];

    YCRecordView *hit = [self recordViewAtPoint:point];

    if (hit != nil) {
        [self.delegate grid:self didTapRecord:hit.record];
        return;
    }

    NSInteger column = [self columnIndexForX:point.x];

    if (column == NSNotFound) {
        return;
    }

    [self.delegate grid:self
        didTapEmptySlotForStaff:[self.staff objectAtIndex:column]
                         atTime:[self dateForY:point.y]];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)press {
    switch (press.state) {
        case UIGestureRecognizerStateBegan:
            [self beginDragAt:press];
            break;

        case UIGestureRecognizerStateChanged:
            _touchInWindow = [press locationInView:nil];
            [self dragToCurrentTouch];
            [self updateAutoScroll];
            break;

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self endDragCancelled:(press.state != UIGestureRecognizerStateEnded)];
            break;

        default:
            break;
    }
}

- (void)beginDragAt:(UILongPressGestureRecognizer *)press {
    CGPoint point = [press locationInView:self];

    YCRecordView *hit = [self recordViewAtPoint:point];

    if (hit == nil) {
        return;
    }

    _dragged = hit;
    _grabOffset = CGPointMake(point.x - hit.frame.origin.x, point.y - hit.frame.origin.y);
    _touchInWindow = [press locationInView:nil];

    hit.lifted = YES;

    [self.delegate grid:self didChangeDragging:YES];

    NSLog(@"[YClients/Календарь] Взята запись %ld", (long)hit.record.recordId);
}

/** Ставит поднятую запись туда, где сейчас палец, с притяжением к сетке. */
- (void)dragToCurrentTouch {
    if (_dragged == nil) {
        return;
    }

    // Через окно, а не locationInView: во время подкрутки палец стоит
    // на месте, а содержимое под ним едет — и координата в сетке меняется
    // сама. Пересчёт из окна учитывает это без единого лишнего условия.
    CGPoint point = [self convertPoint:_touchInWindow fromView:nil];

    CGFloat left = point.x - _grabOffset.x;
    CGFloat top = point.y - _grabOffset.y;

    NSInteger column = [self columnIndexForX:left + self.columnWidth / 2.0];

    if (column == NSNotFound) {
        return;
    }

    NSDate *time = [self dateForY:top];

    CGRect frame = _dragged.frame;

    frame.origin.x = column * self.columnWidth + 1.0;
    frame.origin.y = [self yForDate:time];

    _dragged.frame = frame;
}

#pragma mark Подкрутка к краю

- (void)updateAutoScroll {
    UIScrollView *scroll = self.scrollView;

    if (scroll == nil) {
        return;
    }

    // Положение пальца относительно видимой части, а не содержимого.
    CGPoint inContent = [scroll convertPoint:_touchInWindow fromView:nil];
    CGFloat visibleY = inContent.y - scroll.contentOffset.y;
    CGFloat height = scroll.bounds.size.height;

    CGFloat direction = 0;

    if (visibleY < YCAutoScrollMargin) {
        direction = -1;
    } else if (visibleY > height - YCAutoScrollMargin) {
        direction = 1;
    }

    _autoScrollDirection = direction;

    if (direction == 0) {
        [self stopAutoScroll];
        return;
    }

    if (_autoScroll == nil) {
        // CADisplayLink, а не NSTimer: подкрутка должна идти в такт
        // с отрисовкой, иначе запись под пальцем дрожит.
        _autoScroll = [CADisplayLink displayLinkWithTarget:self
                                                  selector:@selector(autoScrollTick)];

        [_autoScroll addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)stopAutoScroll {
    [_autoScroll invalidate];
    _autoScroll = nil;
}

- (void)autoScrollTick {
    UIScrollView *scroll = self.scrollView;

    if (scroll == nil || _dragged == nil) {
        [self stopAutoScroll];
        return;
    }

    CGFloat offset = scroll.contentOffset.y + YCAutoScrollStep * _autoScrollDirection;
    CGFloat limit = scroll.contentSize.height - scroll.bounds.size.height;

    if (offset < 0) {
        offset = 0;
    }

    if (offset > limit) {
        offset = MAX(0, limit);
    }

    if (offset == scroll.contentOffset.y) {
        // Приехали к краю — дальше крутить некуда.
        [self stopAutoScroll];
        return;
    }

    scroll.contentOffset = CGPointMake(scroll.contentOffset.x, offset);

    [self dragToCurrentTouch];
}

#pragma mark Отпускание

- (void)endDragCancelled:(BOOL)cancelled {
    [self stopAutoScroll];

    YCRecordView *dragged = _dragged;

    if (dragged == nil) {
        return;
    }

    _dragged = nil;
    dragged.lifted = NO;

    [self.delegate grid:self didChangeDragging:NO];

    if (cancelled) {
        // Отмена — например, входящий звонок. Возвращаем на место.
        [self setNeedsLayout];
        return;
    }

    YCRecord *record = dragged.record;

    NSInteger column = [self columnIndexForX:CGRectGetMidX(dragged.frame)];
    NSDate *time = [self dateForY:dragged.frame.origin.y];

    if (column == NSNotFound) {
        [self setNeedsLayout];
        return;
    }

    YCStaff *staff = [self.staff objectAtIndex:column];

    BOOL sameTime = fabs([time timeIntervalSinceDate:record.start]) < 1.0;
    BOOL sameStaff = (staff.staffId == record.staffId);

    if (sameTime && sameStaff) {
        // Не сдвинули. Раскладка вернёт вид на точное место — палец мог
        // оставить его на полточки в стороне.
        [self setNeedsLayout];
        return;
    }

    /**
     * Запись переставляется до ответа сервера.
     *
     * Иначе прямоугольник прыгает обратно и через секунду снова вперёд —
     * и этот прыжок читается как «не получилось», хотя всё получилось.
     * Обязательство за это лежит на вызывающем: при отказе он перезагружает
     * день и тем возвращает всё как было.
     */
    record.start = time;
    record.staffId = staff.staffId;

    [dragged setRecord:record];
    [self setNeedsLayout];

    [self.delegate grid:self didMoveRecord:record toStaff:staff time:time];
}

@end
