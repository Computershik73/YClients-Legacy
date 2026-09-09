#import "YCClientRecordsController.h"

#import "YCAlert.h"
#import "YCApi.h"
#import "YCModel.h"
#import "YCTheme.h"
#import "YCTime.h"

@implementation YCClientRecordsController {
    NSInteger _clientId;
    NSString *_name;
    NSString *_phone;

    NSArray *_records;
    NSArray *_staff;
    BOOL _loading;

    UIActivityIndicatorView *_spinner;
    UILabel *_empty;
}

- (id)initWithClientId:(NSInteger)clientId
                  name:(NSString *)name
                 phone:(NSString *)phone {
    self = [super initWithStyle:UITableViewStylePlain buttonTitle:@"Записать снова"];

    if (self != nil) {
        _clientId = clientId;
        _name = [name copy];
        _phone = [phone copy];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = [_name length] > 0 ? _name : @"Клиент";

    self.tableView.rowHeight = 76.0;

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:[YCTheme spinnerStyle]];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    _empty = [[UILabel alloc] initWithFrame:CGRectZero];
    _empty.text = @"Записей у этого клиента нет.";
    _empty.font = [YCTheme bodyFont];
    _empty.textColor = [YCTheme mutedText];
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.backgroundColor = [UIColor clearColor];
    _empty.numberOfLines = 0;
    _empty.hidden = YES;
    [self.view addSubview:_empty];

    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;

    _spinner.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    _empty.frame = CGRectMake(16, CGRectGetMidY(bounds) - 40, bounds.size.width - 32, 60);
}

#pragma mark Данные

- (void)reload {
    if (_loading) {
        return;
    }

    _loading = YES;
    _empty.hidden = YES;

    [_spinner startAnimating];

    /**
     * Сотрудники грузятся заодно.
     *
     * Они нужны не списку, а тому, что за ним: чтобы записать клиента
     * снова, форме записи нужен полный набор сотрудников — иначе в ней
     * нечего будет выбрать. Запрашивать их в момент нажатия значило бы
     * заставить ждать ровно тогда, когда человек уже на линии.
     */
    [[YCApi shared] loadStaffWithCompletion:^(NSArray *staff, NSString *error) {
        self->_staff = staff;
    }];

    [[YCApi shared] loadVisitsForClient:_clientId completion:^(NSArray *records, NSString *error) {
        self->_loading = NO;

        [self->_spinner stopAnimating];

        if (error != nil) {
            YCAlertMessage(self, @"Записи не получены", error);
            return;
        }

        self->_records = records;
        self->_empty.hidden = ([records count] > 0);

        [self.tableView reloadData];
    }];
}

#pragma mark Список

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_records count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    YCRecord *record = [_records objectAtIndex:path.row];

    [YCTheme decorateCell:cell];

    cell.textLabel.text = [NSString stringWithFormat:@"%@, %@",
                           YCTitleFromDate(record.start), YCClockFromDate(record.start)];
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];

    /**
     * Вторая строка — услуги и комментарий вместе.
     *
     * Именно это и вспоминают: «стрижка, красили в тёмный». Комментарий
     * без услуг встречается не реже — запись могли завести на слух, —
     * поэтому пустая часть просто пропускается, а не оставляет тире
     * посреди строки.
     */
    NSMutableArray *parts = [NSMutableArray array];

    if ([record.services length] > 0) {
        [parts addObject:record.services];
    }

    if ([record.comment length] > 0) {
        [parts addObject:record.comment];
    }

    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [YCTheme captionFont];
    cell.detailTextLabel.textColor = [YCTheme mutedText];

    // Цветная точка слева — то же состояние, что и в календаре.
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 12)];

    [YCTheme decoratePanel:dot
                     color:[YCTheme statusColorForAttendance:record.attendance]
                    radius:6.0];

    UIGraphicsBeginImageContextWithOptions(dot.bounds.size, NO, 0);
    [dot.layer renderInContext:UIGraphicsGetCurrentContext()];
    cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    YCRecord *record = [_records objectAtIndex:path.row];

    YCRecordFormController *form =
        [[YCRecordFormController alloc] initWithRecord:record staff:(_staff ?: @[])];

    form.delegate = self.delegate;

    [self.navigationController pushViewController:form animated:YES];
}

#pragma mark Записать снова

- (void)buttonTapped {
    if ([_staff count] == 0) {
        YCAlertMessage(self, @"Сотрудники ещё не загружены",
                       @"Подождите пару секунд и попробуйте снова.");
        return;
    }

    /**
     * Новая запись — тому же сотруднику, что и в прошлый раз.
     *
     * Клиент чаще возвращается к своему мастеру, чем к любому: это
     * догадка, но догадка верная в подавляющем большинстве случаев,
     * а поменять сотрудника в форме — одно нажатие. Если прошлых
     * записей нет, берётся первый по списку.
     */
    YCStaff *chosen = [_staff objectAtIndex:0];

    if ([_records count] > 0) {
        YCRecord *last = [_records objectAtIndex:0];

        for (YCStaff *member in _staff) {
            if (member.staffId == last.staffId) {
                chosen = member;
                break;
            }
        }
    }

    /**
     * Время — ближайший круглый час завтрашнего дня.
     *
     * Записывать «прямо сейчас» бессмысленно: человек звонит, чтобы
     * прийти потом. Точное время всё равно выбирают в форме, и какое
     * начальное значение здесь — лишь способ не открывать форму пустой.
     */
    NSDate *when = YCDayByAdding(YCStartOfDay([NSDate date]), 1);

    when = [when dateByAddingTimeInterval:10 * 3600];

    YCRecordFormController *form =
        [[YCRecordFormController alloc] initWithNewRecordForStaff:chosen
                                                           atTime:when
                                                            staff:_staff];

    form.delegate = self.delegate;

    /**
     * Имя и телефон подставляются сразу.
     *
     * Ради этого экран и заведён: человек уже на линии, и набирать его
     * телефон заново, когда он тут же в карточке, — работа впустую.
     */
    [form prefillClientName:_name phone:_phone];

    [self.navigationController pushViewController:form animated:YES];
}

@end
