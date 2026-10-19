#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// 小蚕的开屏会轮换多个 SDK（实测出现过 Oct、GDT、BTP）。
// 它们的共同点是都用 windowLevel 2001 的独立 UIWindow 承载开屏，
// 因此统一在窗口层拦掉；GDT 额外补一次关闭回调，避免启动流程等待。
static BOOL XCIsSplashAdWindow(UIWindow *window) {
    if (!window) return NO;
    CGFloat level = window.windowLevel;
    if (level < 2000.0 || level > 2100.0) return NO;

    NSString *rootName = NSStringFromClass([window.rootViewController class]);
    if (!rootName) return YES;
    if ([rootName rangeOfString:@"Input"].location != NSNotFound) return NO;
    if ([rootName rangeOfString:@"TextEffects"].location != NSNotFound) return NO;
    if ([rootName rangeOfString:@"Keyboard"].location != NSNotFound) return NO;
    return YES;
}

// 只拦显示还不够：App 在等广告 SDK 的关闭回调。
// 主动触发广告自身的“跳过/关闭”控件，让 SDK 走正常结束流程。
static void XCTapSkipControls(UIView *view, NSUInteger depth) {
    if (!view || depth > 12) return;

    if ([view isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)view;
        NSString *title = @"";
        if ([control isKindOfClass:[UIButton class]]) {
            title = [(UIButton *)control titleForState:UIControlStateNormal] ?: @"";
        }
        NSString *cls = NSStringFromClass([control class]) ?: @"";
        if ([title containsString:@"跳过"] || [title containsString:@"关闭"] ||
            [cls containsString:@"Skip"] || [cls containsString:@"Close"]) {
            [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
    }

    for (UIView *subview in view.subviews) {
        XCTapSkipControls(subview, depth + 1);
    }
}

static void XCScheduleSkipTaps(UIWindow *window) {
    for (int i = 1; i <= 15; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * i * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            XCTapSkipControls(window, 0);
        });
    }
}

// 窗口必须真正进入 window 层级，广告控件才会响应跳过；
// 因此让它显示但保持全透明，并持续兜底置零 alpha。
static void XCKeepInvisible(UIWindow *window) {
    for (int i = 1; i <= 15; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * i * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (window.alpha != 0.0) {
                window.alpha = 0.0;
            }
        });
    }
}

%hook UIWindow

- (void)makeKeyAndVisible {
    if (XCIsSplashAdWindow(self)) {
        self.alpha = 0.0;
        %orig;
        XCScheduleSkipTaps(self);
        XCKeepInvisible(self);
        return;
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && XCIsSplashAdWindow(self)) {
        self.alpha = 0.0;
        %orig;
        XCScheduleSkipTaps(self);
        XCKeepInvisible(self);
        return;
    }
    %orig;
}

%end

// 仅处理已在小蚕 3.21.6 真机验证的 GDT 开屏路径。
// 跳过实际展示，同时通知广告 delegate 开屏关闭，让 App 继续启动。
%hook GDTSplashAd

- (void)showAdInWindow:(UIWindow *)window
        withBottomView:(UIView *)bottomView
              skipView:(UIView *)skipView {
    SEL delegateSelector = sel_registerName("delegate");
    SEL closedSelector = sel_registerName("splashAdClosed:");

    id ad = (id)self;
    id delegate = nil;
    if ([ad respondsToSelector:delegateSelector]) {
        delegate = ((id (*)(id, SEL))objc_msgSend)(ad, delegateSelector);
    }

    if (delegate && [delegate respondsToSelector:closedSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(delegate, closedSelector, ad);
        return;
    }

    // SDK/版本行为不匹配时保留原广告展示，避免卡住启动流程。
    %orig;
}

%end
