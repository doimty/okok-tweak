#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

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

%hook UIWindow

- (void)makeKeyAndVisible {
    if (XCIsSplashAdWindow(self)) return;
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && XCIsSplashAdWindow(self)) return;
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
