#import "YCStaffPickerController.h"

#import <QuartzCore/QuartzCore.h>

#import "YCIcons.h"
#import "YCTheme.h"

#pragma mark - Сотрудник

@implementation YCStaffPickerController {
    NSArray *_staff;
    NSInteger _selected;
    void (^_onChoose)(YCStaff *);
}

- (id)initWithStaff:(NSArray *)staff
           selected:(NSInteger)staffId
           onChoose:(void (^)(YCStaff *))onChoose {
    self = [super initWithStyle:UITableViewStylePlain buttonTitle:@"Сохранить"];

    if (self != nil) {
        _staff = staff;
        _selected = staffId;
        _onChoose = [onChoose copy];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Сотрудник";
    self.tableView.rowHeight = [YCTheme rowHeight] + 6;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    // «Сбросить» — серой таблеткой над кнопкой, как в оригинале. Оба вида
    // прибиты к низу экрана; отступ таблицы под них считает YCFormScreen.
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeCustom];

    reset.frame = CGRectMake(0, 0, 150, 38);
    [YCTheme decorateButton:reset color:[YCTheme surface] radius:19.0];

    reset.titleLabel.font = [YCTheme bodyFont];
    [reset setTitle:@"✕  Сбросить" forState:UIControlStateNormal];
    [reset setTitleColor:[YCTheme text] forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside];

    self.accessoryView = reset;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_staff count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    YCStaff *member = [_staff objectAtIndex:path.row];

    [YCTheme decorateCell:cell];
    cell.textLabel.text = member.name;
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.text = member.specialization;
    cell.detailTextLabel.textColor = [YCTheme mutedText];
    cell.imageView.image = [YCIcons avatar:[YCTheme avatarSize]];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (member.staffId == _selected) {
        cell.accessoryView = [[UIImageView alloc]
            initWithImage:[YCIcons check:24 color:[YCTheme accent]]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    _selected = [(YCStaff *)[_staff objectAtIndex:path.row] staffId];
    [tableView reloadData];
}

- (void)reset {
    _selected = 0;
    [self.tableView reloadData];
}

- (void)buttonTapped {
    YCStaff *chosen = nil;

    for (YCStaff *member in _staff) {
        if (member.staffId == _selected) {
            chosen = member;
        }
    }

    if (_onChoose != NULL) {
        _onChoose(chosen);
    }

    [self.navigationController popViewControllerAnimated:YES];
}

@end


#pragma mark - Услуга

@implementation YCServicePickerController {
    NSArray *_services;
    NSInteger _selected;
    void (^_onChoose)(YCService *);
}

- (id)initWithServices:(NSArray *)services
              selected:(NSInteger)serviceId
              onChoose:(void (^)(YCService *))onChoose {
    // У пустого списка кнопки нет: сохранять нечего, и жёлтая кнопка
    // под надписью «Сотрудник не оказывает услуг» обещала бы обратное.
    self = [super initWithStyle:UITableViewStylePlain
                    buttonTitle:([services count] > 0 ? @"Сохранить" : nil)];

    if (self != nil) {
        _services = services;
        _selected = serviceId;
        _onChoose = [onChoose copy];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Выбор услуги";
    self.tableView.rowHeight = [YCTheme rowHeight] + 4;

    if ([_services count] == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:
            CGRectMake(0, 20, self.view.bounds.size.width, 28)];

        empty.text = @"Сотрудник не оказывает услуг";
        empty.font = [YCTheme bodyFont];
        empty.textColor = [YCTheme text];
        empty.textAlignment = NSTextAlignmentCenter;
        empty.backgroundColor = [UIColor clearColor];
        empty.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        UIView *header = [[UIView alloc] initWithFrame:
            CGRectMake(0, 0, self.view.bounds.size.width, 68)];

        header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addSubview:empty];

        self.tableView.tableHeaderView = header;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_services count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    YCService *service = [_services objectAtIndex:path.row];

    [YCTheme decorateCell:cell];
    cell.textLabel.text = service.title;
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];

    NSMutableArray *details = [NSMutableArray array];

    if (service.price > 0) {
        [details addObject:[NSString stringWithFormat:@"%.0f ₽", service.price]];
    }

    if (service.duration > 0) {
        [details addObject:[NSString stringWithFormat:@"%.0f мин", service.duration / 60.0]];
    }

    cell.detailTextLabel.text = [details componentsJoinedByString:@" · "];
    cell.detailTextLabel.textColor = [YCTheme mutedText];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (service.serviceId == _selected) {
        cell.accessoryView = [[UIImageView alloc]
            initWithImage:[YCIcons check:24 color:[YCTheme accent]]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    _selected = [(YCService *)[_services objectAtIndex:path.row] serviceId];
    [tableView reloadData];
}

- (void)buttonTapped {
    YCService *chosen = nil;

    for (YCService *service in _services) {
        if (service.serviceId == _selected) {
            chosen = service;
        }
    }

    if (_onChoose != NULL) {
        _onChoose(chosen);
    }

    [self.navigationController popViewControllerAnimated:YES];
}

@end
