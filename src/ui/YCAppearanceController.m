#import "YCAppearanceController.h"

#import "YCIcons.h"
#import "YCTheme.h"

@implementation YCAppearanceController

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Оформление";
    self.tableView.rowHeight = [YCTheme rowHeight];

    [YCTheme decorateTable:self.tableView color:[YCTheme surface]];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    BOOL modern = [[UIDevice currentDevice].systemVersion floatValue] >= 13.0;

    // Про iOS до 13 сказано прямо: там системной темы нет, и «как в системе»
    // не может означать ничего, кроме светлой. Иначе выбор выглядел бы
    // неработающим.
    return modern
        ? @"«Как в системе» повторяет настройку iOS и меняется вместе с ней."
        : @"На этой версии iOS системной темы нет — «как в системе» означает светлую.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                               reuseIdentifier:nil];

    NSArray *titles = @[ @"Как в системе", @"Светлая", @"Тёмная" ];

    cell.textLabel.text = [titles objectAtIndex:path.row];
    cell.textLabel.font = [YCTheme rowFont];
    cell.textLabel.textColor = [YCTheme text];
    [YCTheme decorateCell:cell];

    if ((NSInteger)[YCTheme appearance] == path.row) {
        cell.accessoryView = [[UIImageView alloc]
            initWithImage:[YCIcons check:24 color:[YCTheme accent]]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    [YCTheme setAppearance:(YCAppearance)path.row];
}

@end
