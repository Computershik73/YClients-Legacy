#import "YCProxyController.h"

#import "YCProxy.h"
#import "YCTheme.h"

typedef enum {
    YCProxySectionSwitch = 0,
    YCProxySectionAddress,
    YCProxySectionCount
} YCProxySection;

@interface YCProxyController () <UITextFieldDelegate>
@end

#ifdef YC_PROXY

@implementation YCProxyController {
    UISwitch *_toggle;
    UITextField *_hostField;
    UITextField *_portField;
}

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Прокси";

    [YCTheme decorateTable:self.tableView color:[YCTheme surface]];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    _toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    _toggle.on = [YCProxy isEnabled];
    _toggle.enabled = [YCProxy isCompiledIn];

    [_toggle addTarget:self
                action:@selector(toggleChanged)
      forControlEvents:UIControlEventValueChanged];

    _hostField = [self fieldWithText:[YCProxy host]
                         placeholder:@"192.168.1.183"];

    _hostField.keyboardType = UIKeyboardTypeURL;
    _hostField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _hostField.returnKeyType = UIReturnKeyNext;

    _portField = [self fieldWithText:[NSString stringWithFormat:@"%ld", (long)[YCProxy port]]
                         placeholder:@"8886"];

    _portField.keyboardType = UIKeyboardTypeNumberPad;
}

- (UITextField *)fieldWithText:(NSString *)text placeholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];

    field.text = text;
    field.placeholder = placeholder;
    field.font = [YCTheme bodyFont];
    field.textColor = [YCTheme text];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.keyboardAppearance = [YCTheme keyboardAppearance];
    field.delegate = self;
    field.enabled = [YCProxy isCompiledIn];

    return field;
}

/**
 * Значения сохраняются при уходе с экрана, а не по кнопке.
 *
 * Кнопка «Сохранить» здесь была бы лишним шагом: полей два, ошибиться
 * в них нечем, а забыть нажать — легко, и тогда прокси остался бы
 * со старым адресом, ничего об этом не сказав.
 */
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.view endEditing:YES];
    [self commit];
}

- (void)commit {
    if (![YCProxy isCompiledIn]) {
        return;
    }

    [YCProxy setHost:_hostField.text];
    [YCProxy setPort:[_portField.text integerValue]];

    // Поля перечитываются обратно: если ввели ерунду — пустой адрес или
    // порт вне диапазона, — YCProxy подставит значение по умолчанию,
    // и на экране должно оказаться то же, что и в настройках.
    _hostField.text = [YCProxy host];
    _portField.text = [NSString stringWithFormat:@"%ld", (long)[YCProxy port]];
}

- (void)toggleChanged {
    // Адрес сохраняется до включения: иначе прокси включился бы со старым,
    // а набранный рядом новый пропал бы.
    [self commit];

    [YCProxy setEnabled:_toggle.on];

    [self.tableView reloadData];
}

#pragma mark Список

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return YCProxySectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == YCProxySectionAddress ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == YCProxySectionAddress ? @"Адрес" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != YCProxySectionSwitch) {
        return nil;
    }

    if (![YCProxy isCompiledIn]) {
        /**
         * В готовой сборке кода прокси нет вовсе.
         *
         * Сказать это прямо важнее, чем показать выключенный переключатель:
         * иначе «включаю, а ничего не происходит» пришлось бы разгадывать.
         */
        return @"В этой сборке поддержки прокси нет — она собирается только "
               @"в отладочной. Соберите без FINALPACKAGE=1: make package ipa";
    }

    if (![YCProxy isSupported]) {
        return @"Этой системе прокси недоступен: он сделан на NSURLSession, "
               @"а она появилась в iOS 7. Обычные запросы работают как "
               @"работали.";
    }

    /**
     * Про снятую проверку сертификата — крупно и без обиняков.
     *
     * Это не примечание, а главное свойство переключателя: пока он включён,
     * соединение открыто тому, кто стоит посередине, а через него идут
     * логин с паролем от YClients.
     */
    return @"Пока прокси включён, приложение принимает любой сертификат — "
           @"иначе перехватчик не заработает, он подменяет сертификат своим. "
           @"Соединение при этом открыто для чтения. Включайте только "
           @"в своей сети и выключайте после отладки.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                               reuseIdentifier:nil];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [YCTheme decorateCell:cell];
    cell.textLabel.font = [YCTheme bodyFont];
    cell.textLabel.textColor = [YCTheme text];

    if (path.section == YCProxySectionSwitch) {
        cell.textLabel.text = @"Через прокси";
        cell.accessoryView = _toggle;

        return cell;
    }

    UITextField *field = (path.row == 0) ? _hostField : _portField;

    cell.textLabel.text = (path.row == 0) ? @"Сервер" : @"Порт";

    CGFloat left = 84.0;

    field.frame = CGRectMake(left, 0,
                             cell.contentView.bounds.size.width - left - 12.0, 44.0);

    field.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;

    [cell.contentView addSubview:field];

    return cell;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _hostField) {
        [_portField becomeFirstResponder];
        return NO;
    }

    [textField resignFirstResponder];

    return NO;
}

@end

#else

/**
 * В готовой сборке экрана нет — как нет и самого прокси.
 *
 * Класс оставлен пустым нарочно: на него ссылается заголовок, и пустая
 * оболочка дешевле, чем условная сборка у каждого, кто его подключает.
 * Ни одной строки и ни одного вида отсюда в двоичный файл не попадает,
 * а попасть на этот экран неоткуда — раздел «Отладка» в «О программе»
 * не показывается, когда прокси не собран.
 */
@implementation YCProxyController
@end

#endif  /* YC_PROXY */
