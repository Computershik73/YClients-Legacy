#import "YCDayController.h"

#import <QuartzCore/QuartzCore.h>

#import "YCAlert.h"
#import "YCApi.h"
#import "YCDayChrome.h"
#import "YCDayGridView.h"
#import "YCIcons.h"
#import "YCRecordDetailController.h"
#import "YCRecordFormController.h"
#import "YCSheet.h"
#import "YCDrawerController.h"
#import "YCMonthController.h"
#import "YCScheduleController.h"
#import "YCTheme.h"
#import "YCTime.h"
#import "YCWeekStrip.h"

/** Шаг списка времени в панели «Новая запись», секунд. */
static const NSTimeInterval YCSlotStep = 5 * 60;

/**
 * Вид-заголовок панели: один вид слева, другой справа.
 *
 * Единственное, ради чего он существует, — intrinsicContentSize: без него
 * панель iOS 11+ сжала бы заголовок в точку. На iOS 6 достаточно кадра,
 * и он тоже задан.
 */
@interface YCBarView : UIView
@property (nonatomic, strong) UIView *leading;
@property (nonatomic, strong) UIView *trailing;
@end

@implementation YCBarView

- (CGSize)intrinsicContentSize {
    return self.bounds.size;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat height = self.bounds.size.height;

    CGRect lead = self.leading.frame;
    lead.origin = CGPointMake(0, (height - lead.size.height) / 2);
    self.leading.frame = lead;

    CGRect trail = self.trailing.frame;
    trail.origin = CGPointMake(self.bounds.size.width - trail.size.width,
                               (height - trail.size.height) / 2);
    self.trailing.frame = trail;
}

@end

@interface YCDayController () <YCDayGridDelegate, UIScrollViewDelegate,
                               YCRecordFormDelegate, YCWeekStripDelegate,
                               YCHeaderViewDelegate, YCScheduleDelegate,
                               UITableViewDataSource, UITableViewDelegate>
@end

@implementation YCDayController {
    UIScrollView *_scroll;
    YCDayGridView *_grid;
    YCRulerView *_ruler;
    YCHeaderView *_header;
    UIView *_corner;
    UIButton *_plus;

    YCWeekStrip *_week;
    UIButton *_today;

    UIButton *_titleButton;
    UIButton *_filterButton;

    UIActivityIndicatorView *_spinner;
    UILabel *_notice;

    NSArray *_staff;          // все сотрудники
    NSArray *_records;
    NSMutableSet *_hiddenStaff;   // номера сотрудников, снятых фильтром «Все»

    NSInteger _loading;
    NSInteger _generation;
    NSInteger _slide;           // сторона, с которой въедет новый день

    /**
     * Расписание на показанный день: номер сотрудника → YCScheduleDay.
     *
     * Пусто, пока сервер не ответил. Отсутствие сотрудника в словаре
     * и пустой список его интервалов — разные вещи: первое значит
     * «не знаем», второе — «выходной», и прятать колонку можно только
     * во втором случае.
     */
    NSDictionary *_schedule;

    /** Показывать ли тех, у кого сегодня выходной. */
    BOOL _showsIdleStaff;

    // Панель выбора времени: сотрудник и список слотов.
    YCStaff *_slotStaff;
    NSMutableArray *_slots;
    YCSheet *_slotSheet;
}

#pragma mark Жизнь экрана

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.day == nil) {
        self.day = YCStartOfDay([self wallClockNow]);
    }

    _hiddenStaff = [NSMutableSet set];

    self.view.backgroundColor = [YCTheme background];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    if ([self respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)]) {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }

    [self buildBars];
    [self buildGrid];
    [self buildBottom];

    [self reloadAll];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self updateTitle];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;

    // Полоса недели — внизу, с отступами, как в оригинале; сетка — над ней.
    CGFloat stripHeight = 64.0;

    _week.frame = CGRectMake(16, bounds.size.height - stripHeight - 12,
                             bounds.size.width - 32, stripHeight);

    _scroll.frame = CGRectMake(0, 0, bounds.size.width, CGRectGetMinY(_week.frame) - 8);

    _today.frame = CGRectMake(bounds.size.width - 16 - 120,
                              CGRectGetMinY(_week.frame) - 56, 120, 44);

    _spinner.center = CGPointMake(CGRectGetMidX(_scroll.frame), CGRectGetMidY(_scroll.frame));
    _notice.frame = CGRectInset(_scroll.frame, 24.0, 0);

    [self relayoutGrid];
}

/** Сейчас — в настенном времени филиала (см. YCTime.h). */
- (NSDate *)wallClockNow {
    static NSDateFormatter *local;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        local = [[NSDateFormatter alloc] init];
        local.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        local.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });

    return YCDateFromAPI([local stringFromDate:[NSDate date]]) ?: [NSDate date];
}

#pragma mark Панель навигации

- (void)buildBars {
    /**
     * Дата слева, фильтр справа — оба в одном виде-заголовке.
     *
     * Первая версия клала их в левую и правую кнопки панели с кадрами,
     * посчитанными через sizeWithFont:. На iOS 14 это рассыпалось: панель
     * там раскладывает кнопки автоматически, кадру не верит и спрашивает
     * у вида его собственный размер — а у кнопки с картинкой и отступами
     * он выходил в ширину одной буквы. Вид-заголовок с честным
     * intrinsicContentSize панель растягивает как есть на всех версиях.
     */
    YCBarView *bar = [[YCBarView alloc] initWithFrame:
        CGRectMake(0, 0, self.view.bounds.size.width - 24, 40)];

    _titleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _titleButton.titleLabel.font = [YCTheme titleFont];
    [_titleButton setTitleColor:[YCTheme text] forState:UIControlStateNormal];
    [_titleButton addTarget:self action:@selector(pickDay)
           forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_titleButton];

    _filterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [YCTheme decorateButton:_filterButton color:[YCTheme surface] radius:10.0];

    _filterButton.titleLabel.font = [YCTheme bodyFont];
    [_filterButton setTitleColor:[YCTheme text] forState:UIControlStateNormal];
    [_filterButton setImage:[YCIcons people:20 color:[YCTheme mutedText]]
                   forState:UIControlStateNormal];
    _filterButton.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    _filterButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 16);
    [_filterButton addTarget:self action:@selector(pickStaffFilter)
            forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_filterButton];

    bar.leading = _titleButton;
    bar.trailing = _filterButton;

    self.navigationItem.titleView = bar;

    /**
     * Кнопка шторки слева — вместо панели вкладок.
     *
     * Панель вкладок занимала сорок девять точек внизу постоянно; здесь
     * то же самое стоит одной кнопки в панели, которая и так есть.
     */
    UIButton *menu = [UIButton buttonWithType:UIButtonTypeCustom];

    menu.frame = CGRectMake(0, 0, 34, 30);
    [menu setImage:[YCIcons menu:22 color:[YCTheme text]] forState:UIControlStateNormal];
    [menu addTarget:self action:@selector(openDrawer)
   forControlEvents:UIControlEventTouchUpInside];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithCustomView:menu];

    [self updateTitle];
}

/**
 * Ищет шторку среди тех, кто нас содержит.
 *
 * Через родителей, а не через ссылку: журнал живёт внутри контроллера
 * навигации, который лежит внутри шторки, и держать на неё поле значило
 * бы обязать всех, кто создаёт журнал, эту ссылку проставить — и забыть
 * её ровно там, где журнал показывают из другого места.
 */
#pragma mark Расписание сотрудника

/**
 * Нажатие по имени в шапке открывает его приёмные часы на этот день.
 *
 * Здесь же, не выходя из журнала: чаще всего расписание вспоминают
 * ровно в тот момент, когда в колонку не встаёт запись, — и уходить
 * за этим в отдельный раздел значит потерять и день, и сотрудника,
 * о которых шла речь.
 */
- (void)headerView:(YCHeaderView *)header didTapStaff:(YCStaff *)staff {
    YCScheduleController *schedule =
        [[YCScheduleController alloc] initWithStaff:staff day:self.day];

    schedule.delegate = self;

    [self.navigationController pushViewController:schedule animated:YES];
}

- (void)scheduleDidChange {
    [self reloadAll];
}

- (void)openDrawer {
    UIViewController *node = self;

    while (node != nil) {
        if ([node isKindOfClass:[YCDrawerController class]]) {
            [(YCDrawerController *)node toggleDrawer];
            return;
        }

        node = node.parentViewController;
    }
}

- (void)updateTitle {
    NSString *title = [YCShortTitleFromDate(self.day) stringByAppendingString:@"  ▾"];

    // Уголок — знаком в тексте, а не картинкой: картинка у UIButton встаёт
    // слева от текста, и переставлять её отступами значит снова считать
    // ширину текста руками, на чём первая версия и сломалась.
    [_titleButton setTitle:title forState:UIControlStateNormal];
    [_titleButton sizeToFit];

    BOOL allShown = [_hiddenStaff count] == 0;
    NSString *filter = allShown ? @"Все"
        : [NSString stringWithFormat:@"%lu", (unsigned long)([_staff count] - [_hiddenStaff count])];

    [_filterButton setTitle:filter forState:UIControlStateNormal];
    [_filterButton sizeToFit];

    [(UIView *)self.navigationItem.titleView setNeedsLayout];

    _today.hidden = YCSameDay(self.day, [self wallClockNow]);
}

#pragma mark Сетка

- (void)buildGrid {
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.backgroundColor = [YCTheme gridPaper];
    _scroll.delegate = self;
    _scroll.directionalLockEnabled = NO;
    [self.view addSubview:_scroll];

    _grid = [[YCDayGridView alloc] initWithFrame:CGRectZero];
    _grid.delegate = self;
    _grid.scrollView = _scroll;
    _grid.day = self.day;
    [_scroll addSubview:_grid];

    _ruler = [[YCRulerView alloc] initWithFrame:CGRectZero];
    [_scroll addSubview:_ruler];

    _header = [[YCHeaderView alloc] initWithFrame:CGRectZero];
    _header.delegate = self;
    [_scroll addSubview:_header];

    _corner = [[UIView alloc] initWithFrame:CGRectZero];
    // Уголок над шкалой — продолжение шапки, значит и вид тот же.
    [YCTheme decoratePanel:_corner color:[YCTheme background] radius:0.0];
    [_scroll addSubview:_corner];

    // «+» в углу над шкалой — новая запись прямо сейчас.
    _plus = [UIButton buttonWithType:UIButtonTypeCustom];
    [_plus setImage:[YCIcons plus:28 color:[YCTheme accent]] forState:UIControlStateNormal];
    [_plus addTarget:self action:@selector(addNow) forControlEvents:UIControlEventTouchUpInside];
    [_corner addSubview:_plus];

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:[YCTheme spinnerStyle]];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    _notice = [[UILabel alloc] initWithFrame:CGRectZero];
    _notice.backgroundColor = [UIColor clearColor];
    _notice.textAlignment = NSTextAlignmentCenter;
    _notice.textColor = [YCTheme mutedText];
    _notice.font = [YCTheme bodyFont];
    _notice.numberOfLines = 0;
    _notice.hidden = YES;
    [self.view addSubview:_notice];
}

- (void)buildBottom {
    _week = [[YCWeekStrip alloc] initWithFrame:CGRectZero];
    _week.delegate = self;
    _week.day = self.day;
    [self.view addSubview:_week];

    // «Сегодня» — белая таблетка над полосой, видна только не сегодня.
    _today = [UIButton buttonWithType:UIButtonTypeCustom];
    [YCTheme decorateButton:_today color:[YCTheme background] radius:22.0];

    // Рамка нужна только плоскому оформлению: у выпуклого она уже нарисована
    // в самой плашке, и вторая легла бы поверх неё прямоугольником.
    if (![YCTheme isLegacy]) {
        _today.layer.borderWidth = 1.0;
        _today.layer.borderColor = [YCTheme border].CGColor;
    }

    _today.titleLabel.font = [YCTheme bodyFont];
    [_today setTitle:@"Сегодня" forState:UIControlStateNormal];
    [_today setTitleColor:[YCTheme text] forState:UIControlStateNormal];
    [_today addTarget:self action:@selector(goToday) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_today];
}

/** Сотрудники, прошедшие фильтр «Все». */
/**
 * Кого показывать колонками.
 *
 * Двумя ситами. Первое — ручное: сотрудники, снятые в «Все». Второе —
 * расписание: у кого сегодня выходной, того в сетке нет. Пустая колонка
 * сотрудника, который сегодня не работает, не просто занимает место —
 * она приглашает записать к нему клиента, а сервер такую запись
 * отклонит, и понять почему будет неоткуда.
 *
 * Второе сито снимается переключателем: расписание бывает не выставлено
 * вовсе, и тогда без него на экране не осталось бы ни одной колонки.
 * Ровно поэтому оно и не применяется, пока сервер не ответил, и поэтому
 * же сотрудник, про которого ответа не было, остаётся на месте.
 */
- (NSArray *)shownStaff {
    NSMutableArray *shown = [NSMutableArray array];

    for (YCStaff *member in _staff) {
        if ([_hiddenStaff containsObject:@(member.staffId)]) {
            continue;
        }

        if (!_showsIdleStaff && [_schedule count] > 0) {
            YCScheduleDay *day = [_schedule objectForKey:@(member.staffId)];

            if (day != nil && !day.isWorking) {
                continue;
            }
        }

        [shown addObject:member];
    }

    /**
     * Если по расписанию не работает никто — показываем всех.
     *
     * Иначе экран оказывался бы пустым в самом обидном случае: график
     * на неделю ещё не выставлен, а записывать надо. Пустая сетка тут
     * читается как поломка, а не как «сегодня никто не работает».
     */
    if ([shown count] == 0) {
        return _staff;
    }

    return shown;
}

- (CGFloat)columnWidthForCount:(NSUInteger)count {
    if (count == 0) {
        return [YCTheme minColumnWidth];
    }

    CGFloat available = self.view.bounds.size.width - [YCTheme rulerWidth];

    return MAX(available / count, [YCTheme minColumnWidth]);
}

- (void)relayoutGrid {
    CGFloat rulerWidth = [YCTheme rulerWidth];
    CGFloat headerHeight = [YCTheme headerHeight];

    NSArray *shown = [self shownStaff];

    _grid.columnWidth = [self columnWidthForCount:[shown count]];
    _header.columnWidth = _grid.columnWidth;

    CGSize grid = [_grid contentSize];

    _grid.frame = CGRectMake(rulerWidth, headerHeight, grid.width, grid.height);
    _ruler.startHour = _grid.startHour;
    _ruler.endHour = _grid.endHour;

    _scroll.contentSize = CGSizeMake(rulerWidth + grid.width, headerHeight + grid.height + 24);

    [self floatChrome];
}

- (void)floatChrome {
    CGFloat rulerWidth = [YCTheme rulerWidth];
    CGFloat headerHeight = [YCTheme headerHeight];

    CGPoint offset = _scroll.contentOffset;
    CGSize grid = [_grid contentSize];

    CGFloat x = MAX(0, offset.x);
    CGFloat y = MAX(0, offset.y);

    _ruler.frame = CGRectMake(x, headerHeight, rulerWidth, grid.height);
    _header.frame = CGRectMake(rulerWidth, y, grid.width, headerHeight);
    _corner.frame = CGRectMake(x, y, rulerWidth, headerHeight);
    _plus.frame = CGRectMake(6, 24, 44, 44);

    [_scroll bringSubviewToFront:_ruler];
    [_scroll bringSubviewToFront:_header];
    [_scroll bringSubviewToFront:_corner];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self floatChrome];
}

- (void)scrollToInterestingHour {
    NSDate *now = [self wallClockNow];
    CGFloat y = 0;

    if (YCSameDay(self.day, now)) {
        y = [_grid yForDate:now] - _scroll.bounds.size.height / 3.0;
    }

    CGFloat limit = _scroll.contentSize.height - _scroll.bounds.size.height;

    _scroll.contentOffset = CGPointMake(0, MAX(0, MIN(y, MAX(0, limit))));

    [self floatChrome];
}

#pragma mark Загрузка

- (void)beginLoading {
    _loading++;
    [_spinner startAnimating];
}

- (void)endLoading {
    _loading--;

    if (_loading <= 0) {
        _loading = 0;
        [_spinner stopAnimating];
    }
}

- (void)reloadAll {
    _generation++;

    NSInteger generation = _generation;

    _grid.day = self.day;
    _week.day = self.day;

    [self updateTitle];

    _notice.hidden = YES;

    [self beginLoading];

    [[YCApi shared] loadStaffWithCompletion:^(NSArray *staff, NSString *error) {
        [self endLoading];

        if (generation != self->_generation) {
            return;
        }

        if (error != nil) {
            [self showNotice:error];
            return;
        }

        self->_staff = staff;

        [self applyStaff];
        [self applyRecords];

        [self loadScheduleForGeneration:generation];
    }];

    [self reloadRecordsForGeneration:generation scrollAfterwards:YES];
}

/**
 * Приёмные часы — отдельным запросом после сотрудников.
 *
 * Отдельным, потому что сервер отвечает на одного сотрудника за раз,
 * и ждать всех, прежде чем показать хоть что-то, незачем: сетка
 * рисуется сразу, а часы доезжают и перекрашивают её.
 */
- (void)loadScheduleForGeneration:(NSInteger)generation {
    [[YCApi shared] loadScheduleForDay:self.day staff:_staff
                            completion:^(NSDictionary *schedule, NSString *error) {
        if (generation != self->_generation) {
            return;
        }

        if (error != nil) {
            // Молча: без расписания сетка работает, просто вся белая.
            NSLog(@"[YClients/Календарь] Расписание не получено: %@", error);
            return;
        }

        self->_schedule = schedule;

        [self applyStaff];
    }];
}

- (void)applyStaff {
    NSArray *shown = [self shownStaff];

    _header.staff = shown;
    _grid.staff = shown;
    _grid.schedule = _schedule;

    [self updateTitle];
    [self relayoutGrid];
}

- (void)reloadRecordsForGeneration:(NSInteger)generation
                  scrollAfterwards:(BOOL)scrollAfterwards {
    [self beginLoading];

    [[YCApi shared] loadRecordsForDay:self.day completion:^(NSArray *records, NSString *error) {
        [self endLoading];

        if (generation != self->_generation) {
            return;
        }

        if (error != nil) {
            [self showNotice:error];
            return;
        }

        self->_records = records;

        [self applyRecords];

        if (scrollAfterwards) {
            [self scrollToInterestingHour];
        }
    }];
}

- (void)applyRecords {
    if (_staff == nil) {
        return;
    }

    _grid.records = _records ?: @[];

    [self relayoutGrid];

    if ([_records count] == 0 && _loading == 0) {
        [self showNotice:@"На этот день записей нет.\nКоснитесь свободного времени, чтобы добавить."];
    } else if ([_records count] > 0) {
        _notice.hidden = YES;
    }

    [self slideInIfNeeded];
}

/**
 * Новый день въезжает со стороны, в которую листали.
 *
 * Двигаются только сетка и надпись о пустом дне — ровно то, что сменилось.
 * Шкала часов и шапка со списком сотрудников остаются на месте: ко дню они
 * отношения не имеют, и их сдвиг читался бы как перезагрузка всего экрана
 * вместо смены даты. Сетка при этом уезжает под шкалу и шапку — те
 * добавлены позже и лежат выше.
 */
- (void)slideInIfNeeded {
    if (_slide == 0) {
        return;
    }

    CGFloat from = _slide > 0 ? self.view.bounds.size.width
                              : -self.view.bounds.size.width;

    _slide = 0;

    CGRect gridHome = _grid.frame;
    CGRect noticeHome = _notice.frame;

    _grid.frame = CGRectOffset(gridHome, from, 0);
    _notice.frame = CGRectOffset(noticeHome, from, 0);
    _grid.alpha = 0.0;

    [UIView animateWithDuration:0.22
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_grid.frame = gridHome;
        self->_notice.frame = noticeHome;
        self->_grid.alpha = 1.0;
    }
                     completion:nil];
}

- (void)showNotice:(NSString *)text {
    _notice.text = text;
    _notice.hidden = NO;
}

#pragma mark Листание дней

- (void)goToDay:(NSDate *)day {
    NSDate *chosen = YCStartOfDay(day);

    /**
     * Направление запоминается здесь, а показывается позже.
     *
     * Записи приходят с сервера, и между нажатием и готовым днём проходит
     * доля секунды или несколько. Двигать сетку в момент нажатия
     * бессмысленно: уезжать будет в пустоту, а въезжать нечему. Поэтому
     * сторона запоминается, а само движение делается там, где новый день
     * готов к показу, — в applyRecords.
     */
    if (self.day != nil && !YCSameDay(chosen, self.day)) {
        _slide = [chosen compare:self.day] == NSOrderedDescending ? 1 : -1;
    }

    self.day = chosen;

    _scroll.contentOffset = CGPointZero;

    [self reloadAll];
}

- (void)goToday {
    [self goToDay:[self wallClockNow]];
}

- (void)weekStrip:(YCWeekStrip *)strip didPickDay:(NSDate *)day {
    [self goToDay:day];
}

/**
 * Дата в панели открывает календарь на месяц, а не барабан.
 *
 * Барабан со списками чисел, месяцев и годов отвечает на вопрос «какое
 * число», а спрашивают другое — «какой день». В барабане не видно ни дня
 * недели, ни выходных, ни того, что послезавтра суббота; чтобы попасть
 * на следующий четверг, приходится считать в уме и крутить три колеса
 * по отдельности. В календаре это одно нажатие.
 *
 * Экран тот же, что открывается из шторки: другого календаря на месяц
 * в приложении нет и заводить второй незачем.
 */
- (void)pickDay {
    YCMonthController *month =
        [[YCMonthController alloc] initWithDay:self.day onChoose:^(NSDate *chosen) {
        [self goToDay:chosen];

        // Выбрали — возвращаемся в журнал: смотреть на календарь дальше
        // незачем, вопрос закрыт.
        [self.navigationController popViewControllerAnimated:YES];
    }];

    [self.navigationController pushViewController:month animated:YES];
}

#pragma mark Фильтр сотрудников

/**
 * «Все» — панель со списком сотрудников и галочками.
 *
 * Снятые прячутся из сетки. Фильтр живёт до перезапуска: помнить его
 * между запусками незачем, утром на стойке нужны все.
 */
- (void)pickStaffFilter {
    if ([_staff count] == 0) {
        return;
    }

    CGFloat rowHeight = [YCTheme rowHeight] + 6;

    UITableView *list = [[UITableView alloc] initWithFrame:
        CGRectMake(0, 0, self.view.bounds.size.width,
                   MIN(rowHeight * [_staff count], 380.0))
                                                     style:UITableViewStylePlain];

    list.dataSource = self;
    list.delegate = self;
    list.tag = 1;
    list.rowHeight = rowHeight;
    list.separatorStyle = UITableViewCellSeparatorStyleNone;
    [YCTheme decorateTable:list color:[YCTheme background]];

    [YCSheet presentWithTitle:@"Сотрудники" content:list buttonTitle:@"Показать" onButton:^{
        [self applyStaff];
        [self applyRecords];
    }];
}

#pragma mark Новая запись

- (void)addNow {
    NSArray *shown = [self shownStaff];

    if ([shown count] == 0) {
        return;
    }

    // Ближайшая четверть часа от текущего момента — или начало дня,
    // если открыт другой день.
    NSDate *now = [self wallClockNow];
    NSTimeInterval seconds = YCSameDay(self.day, now)
        ? ceil(YCSecondsIntoDay(now) / [YCTheme timeStep]) * [YCTheme timeStep]
        : 10 * 3600;

    [self openFormForStaff:[shown objectAtIndex:0] atTime:YCDateWithSecondsIntoDay(self.day, seconds)];
}

- (void)openFormForStaff:(YCStaff *)staff atTime:(NSDate *)time {
    YCRecordFormController *form =
        [[YCRecordFormController alloc] initWithNewRecordForStaff:staff atTime:time staff:_staff];

    form.delegate = self;

    YCPresentModal(self, form);
}

/**
 * Тап по свободной клетке — панель со списком времени с шагом пять минут,
 * как в оригинале: сетка попадает в четверть часа, а точное время
 * выбирается уже пальцем по списку.
 */
- (void)grid:(YCDayGridView *)grid
    didTapEmptySlotForStaff:(YCStaff *)staff
                     atTime:(NSDate *)time {
    _slotStaff = staff;
    _slots = [NSMutableArray array];

    NSTimeInterval from = YCSecondsIntoDay(time);

    for (NSInteger i = 0; i < 12 && from + i * YCSlotStep < 24 * 3600; i++) {
        [_slots addObject:YCDateWithSecondsIntoDay(self.day, from + i * YCSlotStep)];
    }

    /**
     * Высота списка — по числу строк, а не круглым числом.
     *
     * Раньше стояло 300 точек при пяти видимых строках из двенадцати:
     * снизу оставалась мёртвая белая полоса, а половина времён была
     * не видна и не очевидна. Потолок в 380 не даёт панели занять экран
     * целиком — затемнение сверху должно оставаться, по нему закрывают.
     */
    CGFloat rowHeight = 52.0;
    CGFloat listHeight = MIN([_slots count] * rowHeight, 380.0);

    UITableView *list = [[UITableView alloc] initWithFrame:
        CGRectMake(0, 0, self.view.bounds.size.width, listHeight)
                                                     style:UITableViewStylePlain];

    list.dataSource = self;
    list.delegate = self;
    list.tag = 2;
    list.rowHeight = rowHeight;
    list.separatorColor = [YCTheme gridLine];
    [YCTheme decorateTable:list color:[YCTheme background]];

    _slotSheet = [YCSheet presentWithTitle:[NSString stringWithFormat:@"Запись · %@", staff.name]
                                   content:list buttonTitle:nil onButton:nil];
}

#pragma mark Таблицы панелей

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return tableView.tag == 1 ? [_staff count] : [_slots count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                               reuseIdentifier:nil];

    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];
    [YCTheme decorateCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (tableView.tag == 1) {
        YCStaff *member = [_staff objectAtIndex:path.row];
        BOOL shown = ![_hiddenStaff containsObject:@(member.staffId)];

        cell.imageView.image = [YCIcons avatar:40];
        cell.textLabel.text = member.name;
        cell.accessoryView = shown
            ? [[UIImageView alloc] initWithImage:[YCIcons check:24 color:[YCTheme accent]]]
            : nil;
    } else {
        cell.textLabel.text = YCClockFromDate([_slots objectAtIndex:path.row]);
        cell.accessoryView = [[UIImageView alloc]
            initWithImage:[YCIcons chevronRight:20 color:[YCTheme mutedText]]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (tableView.tag == 1) {
        NSNumber *identifier = @([(YCStaff *)[_staff objectAtIndex:path.row] staffId]);

        if ([_hiddenStaff containsObject:identifier]) {
            [_hiddenStaff removeObject:identifier];
        } else if ([_hiddenStaff count] + 1 < [_staff count]) {
            // Последнего не спрятать: пустая сетка не показывает ничего.
            [_hiddenStaff addObject:identifier];
        }

        [tableView reloadData];
        return;
    }

    NSDate *time = [_slots objectAtIndex:path.row];
    YCStaff *staff = _slotStaff;

    [_slotSheet dismissThen:^{
        [self openFormForStaff:staff atTime:time];
    }];
}

#pragma mark YCDayGridDelegate

- (void)grid:(YCDayGridView *)grid didChangeDragging:(BOOL)dragging {
    _scroll.scrollEnabled = !dragging;
}

- (void)grid:(YCDayGridView *)grid didTapRecord:(YCRecord *)record {
    YCRecordDetailController *detail =
        [[YCRecordDetailController alloc] initWithRecord:record staff:_staff];

    detail.delegate = self;

    [self.navigationController pushViewController:detail animated:YES];
}

- (void)grid:(YCDayGridView *)grid
    didMoveRecord:(YCRecord *)record
          toStaff:(YCStaff *)staff
             time:(NSDate *)time {
    [self moveRecord:record toStaff:staff time:time saveIfBusy:NO];
}

- (void)moveRecord:(YCRecord *)record
           toStaff:(YCStaff *)staff
              time:(NSDate *)time
        saveIfBusy:(BOOL)saveIfBusy {
    [self beginLoading];

    NSInteger generation = _generation;

    [[YCApi shared] moveRecord:record toStart:time staff:staff.staffId
                    saveIfBusy:saveIfBusy completion:^(BOOL ok, NSString *error) {
        [self endLoading];

        if (ok) {
            [self reloadRecordsForGeneration:generation scrollAfterwards:NO];
            return;
        }

        if (!saveIfBusy) {
            YCAlertConfirm(self, @"Время занято",
                           [NSString stringWithFormat:@"%@\n\nПоставить запись всё равно?", error],
                           @"Поставить", NO, ^{
                [self moveRecord:record toStaff:staff time:time saveIfBusy:YES];
            });

            [self reloadRecordsForGeneration:generation scrollAfterwards:NO];
            return;
        }

        YCAlertMessage(self, @"Не перенеслась", error);
        [self reloadRecordsForGeneration:generation scrollAfterwards:NO];
    }];
}

#pragma mark YCRecordFormDelegate

- (void)recordFormDidChangeRecords:(YCRecordFormController *)form {
    [self reloadRecordsForGeneration:_generation scrollAfterwards:NO];
}

@end
