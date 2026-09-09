#import "YCClientPickerController.h"

#import "YCAlert.h"
#import "YCApi.h"
#import "YCIcons.h"
#import "YCModel.h"
#import "YCTheme.h"

@interface YCClientPickerController () <UISearchBarDelegate>
@end

@implementation YCClientPickerController {
    NSArray *_clients;
    NSString *_query;
    NSInteger _generation;

    UISearchBar *_search;
    UIActivityIndicatorView *_spinner;
    UILabel *_empty;

    void (^_onChoose)(YCClient *);
}

- (id)initWithQuery:(NSString *)query onChoose:(void (^)(YCClient *))onChoose {
    self = [super initWithStyle:UITableViewStylePlain];

    if (self != nil) {
        _query = [query copy] ?: @"";
        _onChoose = [onChoose copy];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Выбор клиента";
    self.tableView.rowHeight = [YCTheme rowHeight];

    [YCTheme decorateTable:self.tableView color:[YCTheme background]];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    _search = [[UISearchBar alloc] initWithFrame:
        CGRectMake(0, 0, self.view.bounds.size.width, 44)];

    _search.placeholder = @"Имя или телефон";
    _search.delegate = self;
    _search.text = _query;
    _search.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    if ([_search respondsToSelector:@selector(setSearchBarStyle:)]) {
        [_search setSearchBarStyle:UISearchBarStyleMinimal];
    }

    [YCTheme decorateSearchBar:_search];

    self.tableView.tableHeaderView = _search;

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:[YCTheme spinnerStyle]];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    _empty = [[UILabel alloc] initWithFrame:CGRectZero];
    _empty.text = @"Никого не нашлось.";
    _empty.font = [YCTheme bodyFont];
    _empty.textColor = [YCTheme mutedText];
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.backgroundColor = [UIColor clearColor];
    _empty.hidden = YES;
    [self.view addSubview:_empty];

    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;

    _spinner.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    _empty.frame = CGRectMake(16, CGRectGetMidY(bounds) - 20, bounds.size.width - 32, 40);
}

#pragma mark Данные

- (void)reload {
    NSInteger generation = ++_generation;

    [_spinner startAnimating];
    _empty.hidden = YES;

    [[YCApi shared] searchClients:_query partial:^(NSArray *clients) {
        // Порция пришла — показываем сразу, как в списке клиентов.
        if (generation != self->_generation) {
            return;
        }

        self->_clients = clients;

        [self.tableView reloadData];
    } completion:^(NSArray *clients, NSString *error) {
        if (generation != self->_generation) {
            return;
        }

        [self->_spinner stopAnimating];

        if (error != nil) {
            YCAlertMessage(self, @"Клиенты не получены", error);
            return;
        }

        self->_clients = clients;
        self->_empty.hidden = ([clients count] > 0);

        [self.tableView reloadData];
    }];
}

#pragma mark Поиск

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    _query = text ?: @"";

    // Задержка, чтобы не слать запрос на каждую букву — как в списке клиентов.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(reload)
                                               object:nil];

    [self performSelector:@selector(reload) withObject:nil afterDelay:0.4];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self reload];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if ([_search isFirstResponder]) {
        [_search resignFirstResponder];
    }
}

#pragma mark Список

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_clients count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:nil];

    YCClient *client = [_clients objectAtIndex:path.row];
    NSString *shown = [client.fullName length] > 0 ? client.fullName : client.name;

    [YCTheme decorateCell:cell];

    cell.imageView.image = [YCIcons avatar:[YCTheme avatarSize]];
    cell.textLabel.text = [shown length] > 0 ? shown : @"Без имени";
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];
    cell.detailTextLabel.text = client.phone;
    cell.detailTextLabel.font = [YCTheme captionFont];
    cell.detailTextLabel.textColor = [YCTheme mutedText];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];

    YCClient *client = [_clients objectAtIndex:path.row];

    if (_onChoose != NULL) {
        _onChoose(client);
    }

    [self.navigationController popViewControllerAnimated:YES];
}

@end
