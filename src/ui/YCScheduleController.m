#import "YCScheduleController.h"

#import "YCAlert.h"
#import "YCApi.h"
#import "YCModel.h"
#import "YCPickerSheet.h"
#import "YCTheme.h"
#import "YCTime.h"

/** Разделы: интервалы и две кнопки под ними. */
typedef enum {
    YCScheduleSectionSlots = 0,
    YCScheduleSectionActions,
    YCScheduleSectionCount
} YCScheduleSection;

typedef enum {
    YCScheduleActionAddSlot = 0,
    YCScheduleActionAddBreak,
    YCScheduleActionDayOff,
    YCScheduleActionCount
} YCScheduleAction;

@implementation YCScheduleController {
    YCStaff *_member;
    NSDate *_day;

    NSMutableArray *_slots;     // YCSlot, по возрастанию
    BOOL _loading;
    BOOL _saving;

    UIActivityIndicatorView *_spinner;
}

- (id)initWithStaff:(YCStaff *)staff day:(NSDate *)day {
    self = [super initWithStyle:UITableViewStyleGrouped buttonTitle:@"Сохранить"];

    if (self != nil) {
        _member = staff;
        _day = day;
        _slots = [NSMutableArray array];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Расписание";

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:[YCTheme spinnerStyle]];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds),
                                  CGRectGetMidY(self.view.bounds));
}

#pragma mark Данные

- (void)reload {
    _loading = YES;

    [_spinner startAnimating];

    [[YCApi shared] loadScheduleForDay:_day staff:@[ _member ]
                            completion:^(NSDictionary *schedule, NSString *error) {
        self->_loading = NO;

        [self->_spinner stopAnimating];

        if (error != nil) {
            YCAlertMessage(self, @"Расписание не получено", error);
            return;
        }

        YCScheduleDay *day = [schedule objectForKey:@(self->_member.staffId)];

        [self->_slots removeAllObjects];
        [self->_slots addObjectsFromArray:day.slots];

        [self.tableView reloadData];
    }];
}

/** Держит интервалы в порядке — иначе перерыв не найти, где резать. */
- (void)sortSlots {
    [_slots sortUsingComparator:^NSComparisonResult(YCSlot *a, YCSlot *b) {
        if (a.from < b.from) return NSOrderedAscending;
        if (a.from > b.from) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

#pragma mark Список

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return YCScheduleSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == YCScheduleSectionSlots) {
        // Строка-заглушка вместо пустого раздела: пустой раздел выглядит
        // как «ещё грузится», а выходной — это ответ.
        return MAX((NSInteger)[_slots count], 1);
    }

    return YCScheduleActionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == YCScheduleSectionSlots) {
        return [NSString stringWithFormat:@"%@ · %@",
                _member.name ?: @"Сотрудник", YCTitleFromDate(_day)];
    }

    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == YCScheduleSectionActions) {
        return @"Перерыв — это промежуток между двумя интервалами: "
               @"день с 10:00 до 19:00 с обедом в два хранится как "
               @"10:00–14:00 и 15:00–19:00.";
    }

    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                               reuseIdentifier:nil];

    [YCTheme decorateCell:cell];

    cell.textLabel.font = [YCTheme rowFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.font = [YCTheme bodyFont];
    cell.detailTextLabel.textColor = [YCTheme mutedText];

    if (path.section == YCScheduleSectionSlots) {
        if ([_slots count] == 0) {
            cell.textLabel.text = @"Выходной";
            cell.textLabel.textColor = [YCTheme mutedText];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        YCSlot *slot = [_slots objectAtIndex:path.row];

        cell.textLabel.text = [NSString stringWithFormat:@"%@ – %@",
                               [slot fromText], [slot toText]];

        /**
         * Под каждым интервалом, кроме первого, подписан перерыв перед ним.
         *
         * Иначе разрезанный день выглядит как два не связанных интервала,
         * и понять, что между ними час обеда, можно только вычитанием
         * в уме.
         */
        if (path.row > 0) {
            YCSlot *previous = [_slots objectAtIndex:path.row - 1];
            NSInteger gap = slot.from - previous.to;

            if (gap > 0) {
                cell.detailTextLabel.text =
                    [NSString stringWithFormat:@"перерыв %ld мин", (long)gap];
            }
        }

        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

        return cell;
    }

    switch (path.row) {
        case YCScheduleActionAddSlot:
            cell.textLabel.text = @"Добавить интервал";
            cell.textLabel.textColor = [YCTheme accent];
            break;

        case YCScheduleActionAddBreak:
            cell.textLabel.text = @"Добавить перерыв";
            cell.textLabel.textColor = [_slots count] > 0 ? [YCTheme accent]
                                                          : [YCTheme mutedText];
            break;

        case YCScheduleActionDayOff:
            cell.textLabel.text = @"Сделать выходным";
            cell.textLabel.textColor = [YCTheme nowLine];
            break;

        default:
            break;
    }

    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    if (path.section == YCScheduleSectionSlots) {
        if ([_slots count] > 0) {
            [self editSlotAt:path.row];
        }

        return;
    }

    switch (path.row) {
        case YCScheduleActionAddSlot:  [self addSlot];  break;
        case YCScheduleActionAddBreak: [self addBreak]; break;
        case YCScheduleActionDayOff:   [self makeDayOff]; break;
        default: break;
    }
}

#pragma mark Удаление интервала

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == YCScheduleSectionSlots && [_slots count] > 0;
}

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)style
         forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) {
        return;
    }

    [_slots removeObjectAtIndex:path.row];

    [tableView reloadData];
}

#pragma mark Правка

/** Минуты от полуночи в дату — колесу нужна именно дата. */
- (NSDate *)dateForMinutes:(NSInteger)minutes {
    return [YCStartOfDay(_day) dateByAddingTimeInterval:minutes * 60];
}

- (NSInteger)minutesFromDate:(NSDate *)date {
    return (NSInteger)(YCSecondsIntoDay(date) / 60);
}

- (void)editSlotAt:(NSInteger)index {
    YCSlot *slot = [_slots objectAtIndex:index];

    [YCPickerSheet presentWithTitle:@"Начало"
                               date:[self dateForMinutes:slot.from]
                               mode:UIDatePickerModeTime
                     minuteInterval:15
                           onChoose:^(NSDate *chosen) {
        NSInteger from = [self minutesFromDate:chosen];

        [YCPickerSheet presentWithTitle:@"Конец"
                                   date:[self dateForMinutes:slot.to]
                                   mode:UIDatePickerModeTime
                         minuteInterval:15
                               onChoose:^(NSDate *end) {
            NSInteger to = [self minutesFromDate:end];

            /**
             * Полночь в конце — это конец суток.
             *
             * Смену «с 20:00 до 00:00» иначе пришлось бы считать
             * интервалом отрицательной длины и отбрасывать, а она
             * обычная у ночных смен.
             */
            if (to == 0 && from > 0) {
                to = 24 * 60;
            }

            if (to <= from) {
                YCAlertMessage(self, @"Конец раньше начала",
                               @"Интервал должен заканчиваться позже, чем начинается.");
                return;
            }

            slot.from = from;
            slot.to = to;

            [self sortSlots];
            [self.tableView reloadData];
        }];
    }];
}

- (void)addSlot {
    /**
     * Новый интервал начинается там, где кончился последний.
     *
     * Не «с десяти до семи» каждый раз: интервалы добавляют, чтобы
     * достроить день, а не чтобы начать его заново. Если день пуст —
     * обычная смена с десяти до семи.
     */
    NSInteger from = 10 * 60;
    NSInteger to = 19 * 60;

    if ([_slots count] > 0) {
        YCSlot *last = [_slots lastObject];

        from = MIN(last.to + 60, 23 * 60);
        to = MIN(from + 4 * 60, 24 * 60);
    }

    [_slots addObject:[YCSlot slotFrom:from to:to]];

    [self sortSlots];
    [self.tableView reloadData];
}

/**
 * Перерыв разрезает интервал надвое.
 *
 * Добавлять нечего: в расписании нет места, куда перерыв мог бы лечь
 * отдельной записью. Поэтому спрашиваем, когда он начинается и когда
 * кончается, находим интервал, внутрь которого он попал, и делим его.
 */
- (void)addBreak {
    if ([_slots count] == 0) {
        YCAlertMessage(self, @"Сначала рабочий интервал",
                       @"Перерыв делит рабочее время надвое — делить пока нечего.");
        return;
    }

    YCSlot *first = [_slots objectAtIndex:0];
    NSInteger suggested = MIN(first.from + 4 * 60, first.to);

    [YCPickerSheet presentWithTitle:@"Перерыв с"
                               date:[self dateForMinutes:suggested]
                               mode:UIDatePickerModeTime
                     minuteInterval:15
                           onChoose:^(NSDate *chosen) {
        NSInteger from = [self minutesFromDate:chosen];

        [YCPickerSheet presentWithTitle:@"Перерыв до"
                                   date:[self dateForMinutes:MIN(from + 60, 24 * 60)]
                                   mode:UIDatePickerModeTime
                         minuteInterval:15
                               onChoose:^(NSDate *end) {
            NSInteger to = [self minutesFromDate:end];

            if (to <= from) {
                YCAlertMessage(self, @"Конец раньше начала",
                               @"Перерыв должен заканчиваться позже, чем начинается.");
                return;
            }

            [self cutBreakFrom:from to:to];
        }];
    }];
}

- (void)cutBreakFrom:(NSInteger)from to:(NSInteger)to {
    NSMutableArray *result = [NSMutableArray array];
    BOOL touched = NO;

    for (YCSlot *slot in _slots) {
        // Перерыв целиком мимо этого интервала — оставляем как есть.
        if (to <= slot.from || from >= slot.to) {
            [result addObject:slot];
            continue;
        }

        touched = YES;

        // Кусок до перерыва и кусок после; вырожденные не добавляются —
        // перерыв мог начинаться ровно с начала интервала.
        if (slot.from < from) {
            [result addObject:[YCSlot slotFrom:slot.from to:MIN(from, slot.to)]];
        }

        if (slot.to > to) {
            [result addObject:[YCSlot slotFrom:MAX(to, slot.from) to:slot.to]];
        }
    }

    if (!touched) {
        YCAlertMessage(self, @"Перерыв вне рабочего времени",
                       @"В это время сотрудник и так не принимает.");
        return;
    }

    [_slots setArray:result];

    [self sortSlots];
    [self.tableView reloadData];
}

- (void)makeDayOff {
    YCAlertConfirm(self, @"Сделать выходным?",
                   @"Все интервалы этого дня будут убраны. Записи, уже стоящие "
                   @"в этот день, никуда не денутся.",
                   @"Сделать", YES, ^{
        [self->_slots removeAllObjects];

        [self.tableView reloadData];
    });
}

#pragma mark Сохранение

- (void)buttonTapped {
    if (_saving || _loading) {
        return;
    }

    // Пересекающиеся интервалы сервер примет, а сетка нарисует кашу.
    for (NSUInteger i = 1; i < [_slots count]; i++) {
        YCSlot *previous = [_slots objectAtIndex:i - 1];
        YCSlot *slot = [_slots objectAtIndex:i];

        if (slot.from < previous.to) {
            YCAlertMessage(self, @"Интервалы пересекаются",
                           [NSString stringWithFormat:@"%@ – %@ и %@ – %@ накладываются.",
                            [previous fromText], [previous toText],
                            [slot fromText], [slot toText]]);
            return;
        }
    }

    _saving = YES;

    [_spinner startAnimating];

    [[YCApi shared] setSchedule:_slots forStaff:_member.staffId onDay:_day
                     completion:^(BOOL ok, NSString *error) {
        self->_saving = NO;

        [self->_spinner stopAnimating];

        if (!ok) {
            YCAlertMessage(self, @"Не сохранилось", error);
            return;
        }

        [self.delegate scheduleDidChange];

        [self.navigationController popViewControllerAnimated:YES];
    }];
}

@end
