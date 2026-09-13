#import "YCRecordDetailController.h"

#import <QuartzCore/QuartzCore.h>

#import "YCAlert.h"
#import "YCApi.h"
#import "YCClientRecordsController.h"
#import "YCIcons.h"
#import "YCTheme.h"
#import "YCTime.h"

typedef enum {
    YCDetailAttendance = 0,
    YCDetailClientTitle,
    YCDetailClient,
    YCDetailStaff,
    YCDetailServices,
    YCDetailComment,
    YCDetailCount
} YCDetailRow;

@implementation YCRecordDetailController {
    YCRecord *_record;
    NSArray *_allStaff;
    UISegmentedControl *_attendance;
    BOOL _busy;
}

- (id)initWithRecord:(YCRecord *)record staff:(NSArray *)allStaff {
    self = [super initWithStyle:UITableViewStylePlain];

    if (self != nil) {
        _record = record;
        _allStaff = allStaff;
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = YCLongTitleFromDate(_record.start);
    [YCTheme decorateTable:self.tableView color:[YCTheme background]];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[YCIcons trash:24 color:[YCTheme nowLine]]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(confirmDelete)];

    /**
     * Посещаемость — сегментами в порядке оригинала.
     *
     * Значения сервера не по порядку: 0 — ожидание, 1 — пришёл,
     * −1 — не пришёл, 2 — подтвердил. Таблица ниже переводит номер
     * сегмента в значение и обратно.
     */
    /**
     * На тесном экране подписи короче.
     *
     * Четыре доли на 320 точках — это 72 точки на каждую, а «Подтвердил»
     * в обычном начертании занимает под восемьдесят: слова наезжали друг
     * на друга и читались как одно. Уменьшить шрифт мало — «Не пришёл»
     * и «Подтвердил» упираются в ширину доли и на девяти пунктах.
     *
     * Слова выбраны так, чтобы не потребовалось вчитываться: «Ждём» —
     * это ожидание, «Не был» — не пришёл. Сокращений с точкой нет
     * нарочно, читать «Подтв.» в списке из четырёх состояний тяжелее,
     * чем короткое, но целое слово.
     */
    BOOL tight = [YCTheme isCompact];

    NSArray *titles = tight
        ? @[ @"Ждём", @"Пришёл", @"Не был", @"Подтвердил" ]
        : @[ @"Ожидание", @"Пришёл", @"Не пришёл", @"Подтвердил" ];

    _attendance = [[UISegmentedControl alloc] initWithItems:titles];

    // Шрифт мельче ровно там, где тесно: на iPad подписи и так помещаются.
    if (tight) {
        [_attendance setTitleTextAttributes:@{
            UITextAttributeFont: [UIFont systemFontOfSize:11.0]
        } forState:UIControlStateNormal];
    }

    if ([_attendance respondsToSelector:@selector(setTintColor:)]) {
        _attendance.tintColor = [YCTheme text];
    }

    [_attendance addTarget:self action:@selector(attendanceChanged)
          forControlEvents:UIControlEventValueChanged];

    [self syncAttendance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.tableView reloadData];
}

static const NSInteger YCAttendanceBySegment[4] = { 0, 1, -1, 2 };

- (void)syncAttendance {
    for (NSInteger i = 0; i < 4; i++) {
        if (YCAttendanceBySegment[i] == _record.attendance) {
            _attendance.selectedSegmentIndex = i;
        }
    }
}

- (void)attendanceChanged {
    NSInteger value = YCAttendanceBySegment[_attendance.selectedSegmentIndex];

    if (value == _record.attendance || _busy) {
        return;
    }

    _busy = YES;

    [[YCApi shared] setAttendance:value ofRecord:_record completion:^(BOOL ok, NSString *error) {
        self->_busy = NO;

        if (!ok) {
            YCAlertMessage(self, @"Статус не изменён", error);
            [self syncAttendance];
            return;
        }

        self->_record.attendance = value;
        [self.delegate recordFormDidChangeRecords:nil];
    }];
}

#pragma mark Список

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return YCDetailCount;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    switch (path.row) {
        case YCDetailAttendance:  return 60.0;
        case YCDetailClientTitle: return 50.0;
        /**
         * Пустой комментарий тоже занимает строку.
         *
         * Раньше строка схлопывалась в ноль, и добавить комментарий
         * к записи, у которой его нет, было неоткуда — а это самая
         * частая правка: в комментарии живут имя, телефон и всё, что
         * не влезло в поля.
         */
        case YCDetailComment:     return 84.0;
        default:                  return [YCTheme formRowHeight];
    }
}

- (UITableViewCell *)plainCell {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.font = [YCTheme captionFont];
    cell.detailTextLabel.textColor = [YCTheme mutedText];

    return cell;
}

/** Серый квадрат с «+» слева — «Выберите клиента», «Добавить услугу». */
- (UIImage *)plusTile {
    UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];

    [YCTheme decoratePanel:tile color:[YCTheme surface] radius:10.0];

    UIImageView *plus = [[UIImageView alloc] initWithImage:[YCIcons plus:22 color:[YCTheme text]]];
    plus.center = CGPointMake(22, 22);
    [tile addSubview:plus];

    UIGraphicsBeginImageContextWithOptions(tile.bounds.size, NO, 0);
    [tile.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return image;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [self plainCell];

    switch (path.row) {
        case YCDetailAttendance: {
            _attendance.frame = CGRectMake(16, 12, cell.contentView.bounds.size.width - 32, 40);
            _attendance.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:_attendance];
            break;
        }

        case YCDetailClientTitle: {
            BOOL none = [_record.clientName length] == 0 && [_record.clientPhone length] == 0;

            cell.textLabel.text = none ? @"Клиент не выбран" : _record.title;
            cell.textLabel.font = [UIFont boldSystemFontOfSize:22.0];
            break;
        }

        case YCDetailClient: {
            BOOL none = [_record.clientName length] == 0 && [_record.clientPhone length] == 0;

            cell.imageView.image = none ? [self plusTile] : [YCIcons avatar:[YCTheme avatarSize]];
            cell.textLabel.text = none ? @"Выберите клиента" : (_record.clientPhone ?: @"");
            cell.textLabel.textColor = none ? [YCTheme mutedText] : [YCTheme text];
            cell.detailTextLabel.text = _record.clientEmail;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }

        case YCDetailStaff: {
            cell.imageView.image = [YCIcons avatar:[YCTheme avatarSize]];
            cell.textLabel.text = [self staffName];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@–%@",
                                         YCClockFromDate(_record.start),
                                         YCClockFromDate(_record.end)];
            cell.detailTextLabel.font = [YCTheme bodyFont];

            // Карандаш справа — правка записи.
            UIButton *pencil = [UIButton buttonWithType:UIButtonTypeCustom];
            pencil.frame = CGRectMake(0, 0, 44, 44);
            [YCTheme decorateButton:pencil color:[YCTheme surface] radius:10.0];
            [pencil setImage:[YCIcons pencil:22 color:[YCTheme text]] forState:UIControlStateNormal];
            [pencil addTarget:self action:@selector(edit) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = pencil;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }

        case YCDetailServices: {
            BOOL none = [_record.services length] == 0;

            cell.imageView.image = none ? [self plusTile] : nil;
            cell.textLabel.text = none ? @"Добавить услугу" : _record.services;
            cell.textLabel.textColor = none ? [YCTheme mutedText] : [YCTheme text];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }

        case YCDetailComment: {
            // Комментарий — в сером скруглённом поле со значком пузыря.
            UIView *bubble = [[UIView alloc] initWithFrame:
                CGRectMake(16, 8, cell.contentView.bounds.size.width - 32, 72)];

            [YCTheme decoratePanel:bubble color:[YCTheme surface]
                            radius:[YCTheme cornerRadius]];
            bubble.autoresizingMask = UIViewAutoresizingFlexibleWidth;

            UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(16, 16, 40, 40)];
            [YCTheme decoratePanel:badge color:[YCTheme mutedText] radius:10.0];

            UIImageView *icon = [[UIImageView alloc]
                initWithImage:[YCIcons comment:24 color:[UIColor whiteColor]]];
            icon.center = CGPointMake(20, 20);
            [badge addSubview:icon];
            [bubble addSubview:badge];

            UILabel *text = [[UILabel alloc] initWithFrame:
                CGRectMake(72, 8, bubble.bounds.size.width - 88, 56)];

            BOOL empty = [_record.comment length] == 0;

            text.text = empty ? @"Добавить комментарий" : _record.comment;
            text.font = [YCTheme bodyFont];
            text.textColor = empty ? [YCTheme mutedText] : [YCTheme text];
            text.numberOfLines = 2;
            text.backgroundColor = [UIColor clearColor];
            text.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [bubble addSubview:text];

            [cell.contentView addSubview:bubble];

            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }

        default:
            break;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    // Всё, что можно менять, меняется в форме — одной, чтобы правка
    // не расходилась по разным экранам с разной проверкой.
    /**
     * Нажатие на клиента ведёт к его записям, если он заведён в базе.
     *
     * От записи в календаре к истории человека — второй ход того же
     * разговора: администратор видит в сетке «Ирина, 14:00», а нужно
     * вспомнить, что ей делали весной. Клиента без номера — записанного
     * на слух, одним комментарием — открывать нечем, и тогда нажатие
     * по-прежнему ведёт в правку.
     */
    if (path.row == YCDetailClient && _record.clientId > 0) {
        YCClientRecordsController *records =
            [[YCClientRecordsController alloc] initWithClientId:_record.clientId
                                                           name:_record.clientName
                                                          phone:_record.clientPhone];

        records.delegate = self.delegate;

        [self.navigationController pushViewController:records animated:YES];
        return;
    }

    if (path.row == YCDetailClient || path.row == YCDetailStaff ||
        path.row == YCDetailServices || path.row == YCDetailComment) {
        [self edit];
    }
}

- (NSString *)staffName {
    for (YCStaff *member in _allStaff) {
        if (member.staffId == _record.staffId) {
            return member.name;
        }
    }

    return [NSString stringWithFormat:@"№%ld", (long)_record.staffId];
}

#pragma mark Действия

- (void)edit {
    YCRecordFormController *form =
        [[YCRecordFormController alloc] initWithRecord:_record staff:_allStaff];

    form.delegate = self.delegate;

    [self.navigationController pushViewController:form animated:YES];
}

- (void)confirmDelete {
    YCAlertConfirm(self, @"Удалить запись?",
                   [NSString stringWithFormat:@"%@, %@ в %@", _record.title,
                    YCTitleFromDate(_record.start), YCClockFromDate(_record.start)],
                   @"Удалить", YES, ^{
        [[YCApi shared] deleteRecord:self->_record completion:^(BOOL ok, NSString *error) {
            if (!ok) {
                YCAlertMessage(self, @"Не удалилась", error);
                return;
            }

            [self.delegate recordFormDidChangeRecords:nil];
            [self.navigationController popViewControllerAnimated:YES];
        }];
    });
}

@end
