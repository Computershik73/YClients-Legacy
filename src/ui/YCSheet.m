#import "YCSheet.h"

#import <QuartzCore/QuartzCore.h>

#import "YCIcons.h"
#import "YCTheme.h"

static const CGFloat YCSheetHandleHeight = 22.0;
static const CGFloat YCSheetTitleHeight = 50.0;
static const CGFloat YCSheetButtonHeight = 56.0;
static const CGFloat YCSheetButtonInset = 16.0;

@interface YCSheet ()
@property (nonatomic, strong) UIView *dimmer;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, copy) dispatch_block_t onButton;
@end

/** Показанные панели держатся здесь — цели у UIControl слабые. */
static NSMutableSet *YCSheetsAlive(void) {
    static NSMutableSet *alive;
    static dispatch_once_t once;

    dispatch_once(&once, ^{ alive = [NSMutableSet set]; });

    return alive;
}

@implementation YCSheet

+ (YCSheet *)presentWithTitle:(NSString *)title
                      content:(UIView *)content
                  buttonTitle:(NSString *)buttonTitle
                     onButton:(dispatch_block_t)onButton {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    if (window == nil) {
        return nil;
    }

    YCSheet *sheet = [[YCSheet alloc] init];

    sheet.onButton = onButton;

    CGRect bounds = window.bounds;
    CGFloat width = bounds.size.width;

    CGFloat height = YCSheetHandleHeight + content.bounds.size.height;

    if ([title length] > 0) {
        height += YCSheetTitleHeight;
    }

    if (buttonTitle != nil) {
        height += YCSheetButtonHeight + YCSheetButtonInset * 2;
    }

    // На безрамочных экранах снизу есть полоса системы; на старых — нет.
    // Запас в 12 точек не мешает нигде.
    height += 12.0;

    // Панель не выше трёх четвертей экрана: остальное — затемнение,
    // по которому закрывают.
    height = MIN(height, bounds.size.height * 0.78);

    sheet.dimmer = [[UIView alloc] initWithFrame:bounds];
    sheet.dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];
    sheet.dimmer.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [sheet.dimmer addGestureRecognizer:
        [[UITapGestureRecognizer alloc] initWithTarget:sheet action:@selector(cancel)]];

    sheet.panel = [[UIView alloc] initWithFrame:CGRectMake(0, bounds.size.height, width, height)];
    sheet.panel.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    // Скругление верхних углов. layer.cornerRadius скругляет все четыре;
    // нижние прячутся за краем экрана, так что снаружи разницы нет.
    [YCTheme decoratePanel:sheet.panel color:[YCTheme background]
                    radius:[YCTheme cornerRadius]];

    sheet.panel.clipsToBounds = YES;

    CGFloat y = 0;

    // Полоска-«ручка» сверху, как у оригинала.
    UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(width / 2 - 20, 8, 40, 4)];
    handle.backgroundColor = [YCTheme gridLine];
    handle.layer.cornerRadius = 2.0;
    handle.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                              UIViewAutoresizingFlexibleRightMargin;
    [sheet.panel addSubview:handle];

    y += YCSheetHandleHeight;

    if ([title length] > 0) {
        UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];

        [close setImage:[YCIcons close:24 color:[YCTheme text]] forState:UIControlStateNormal];
        close.frame = CGRectMake(12, y, 44, YCSheetTitleHeight);
        [close addTarget:sheet action:@selector(cancel)
        forControlEvents:UIControlEventTouchUpInside];
        [sheet.panel addSubview:close];

        UILabel *caption = [[UILabel alloc] initWithFrame:
            CGRectMake(60, y, width - 76, YCSheetTitleHeight)];

        caption.text = title;
        caption.font = [YCTheme titleFont];
        caption.textColor = [YCTheme text];
        caption.backgroundColor = [UIColor clearColor];
        caption.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [sheet.panel addSubview:caption];

        y += YCSheetTitleHeight;

        UIView *rule = [[UIView alloc] initWithFrame:CGRectMake(0, y - 0.5, width, 0.5)];
        rule.backgroundColor = [YCTheme gridLine];
        rule.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [sheet.panel addSubview:rule];
    }

    CGFloat bottomReserved = 12.0 + (buttonTitle != nil
        ? YCSheetButtonHeight + YCSheetButtonInset * 2 : 0);

    content.frame = CGRectMake(0, y, width, height - y - bottomReserved);
    content.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [sheet.panel addSubview:content];

    if (buttonTitle != nil) {
        UIButton *button = [YCSheet yellowButtonWithTitle:buttonTitle];

        button.frame = CGRectMake(YCSheetButtonInset,
                                  height - 12.0 - YCSheetButtonInset - YCSheetButtonHeight,
                                  width - YCSheetButtonInset * 2, YCSheetButtonHeight);
        button.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                  UIViewAutoresizingFlexibleTopMargin;
        [button addTarget:sheet action:@selector(choose)
         forControlEvents:UIControlEventTouchUpInside];
        [sheet.panel addSubview:button];
    }

    [window addSubview:sheet.dimmer];
    [window addSubview:sheet.panel];

    [YCSheetsAlive() addObject:sheet];

    [UIView animateWithDuration:0.25 animations:^{
        sheet.dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];

        CGRect frame = sheet.panel.frame;

        frame.origin.y = window.bounds.size.height - frame.size.height;
        sheet.panel.frame = frame;
    }];

    return sheet;
}

/** Жёлтая кнопка на всю ширину — главная кнопка каждого экрана оригинала. */
+ (UIButton *)yellowButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];

    [YCTheme decorateButton:button color:[YCTheme accent] radius:[YCTheme buttonRadius]];

    button.titleLabel.font = [YCTheme titleFont];

    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[YCTheme text] forState:UIControlStateNormal];
    [button setTitleColor:[YCTheme mutedText] forState:UIControlStateDisabled];

    return button;
}

- (void)dismissThen:(dispatch_block_t)then {
    [UIView animateWithDuration:0.2 animations:^{
        self.dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];

        CGRect frame = self.panel.frame;

        frame.origin.y = self.dimmer.bounds.size.height;
        self.panel.frame = frame;
    } completion:^(BOOL finished) {
        [self.dimmer removeFromSuperview];
        [self.panel removeFromSuperview];

        if (then != NULL) {
            then();
        }

        [YCSheetsAlive() removeObject:self];
    }];
}

- (void)cancel {
    [self dismissThen:NULL];
}

- (void)choose {
    dispatch_block_t action = self.onButton;

    [self dismissThen:action];
}

@end


#pragma mark - Модальные экраны

/**
 * Обёртка, которая закрывает себя по ×.
 *
 * Крестик надо на что-то повесить, а экраны внутри о том, как их показали,
 * знать не должны — они те же, что и при обычном переходе в навигации.
 */
@interface YCModalHost : UINavigationController
@end

@implementation YCModalHost

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

void YCPresentModal(UIViewController *host, UIViewController *screen) {
    YCModalHost *navigation = [[YCModalHost alloc] initWithRootViewController:screen];

    // Модальная навигация — своя панель, и UIAppearance ей тоже не хватает:
    // с iOS 7 панель прозрачна, и тёмный цвет без этого размывается в серый.
    [YCTheme decorateNavigationController:navigation];

    // Модальная навигация — своя, и панель UIAppearance ей тоже не докрасит.
    [YCTheme decorateNavigationController:navigation];

    UIBarButtonItem *close =
        [[UIBarButtonItem alloc] initWithImage:[YCIcons close:24 color:[YCTheme text]]
                                         style:UIBarButtonItemStylePlain
                                        target:navigation
                                        action:@selector(closeTapped)];

    screen.navigationItem.leftBarButtonItem = close;

    [host presentViewController:navigation animated:YES completion:nil];
}

void YCDismissModal(UIViewController *screen) {
    UIViewController *presented = screen.navigationController ?: screen;

    [presented.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}
