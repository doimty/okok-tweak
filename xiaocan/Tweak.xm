#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// 小蚕 3.21.6 的开屏广告由 XiaoCanAd.AdSplashBU 管理，
// 广告以 windowLevel ≈ 2001 的独立 UIWindow 展示。
// 实测链路：splashAdLoadSuccess: -> 窗口显示 -> splashAdRenderSuccess: -> splashAdWillShow:
// 之后要等约 6.5 秒 SDK 才发 splashAdDidClose:closeType:，App 才继续启动。
// 因此：窗口保持透明显示让 SDK 状态机正常推进，在 WillShow 后主动调用 App 自己的
// splashAdDidClose:closeType:，让 Flutter 立刻拿到“开屏结束”并进入首页。
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

static void XCKeepInvisible(UIWindow *window) {
    window.userInteractionEnabled = NO;
    for (int i = 1; i <= 15; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * i * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (window.alpha != 0.0) {
                window.alpha = 0.0;
            }
            window.userInteractionEnabled = NO;
        });
    }
}

static __weak id gSplashBU;
static __weak id gSplashAd;
static __weak UIWindow *gSplashWindow;
static BOOL gSplashClosed;

static void XCFinishSplash(id bu, id ad) {
    if (gSplashClosed) return;
    if (!bu) bu = gSplashBU;
    if (!ad) ad = gSplashAd;
    if (!bu) return;

    gSplashClosed = YES;

    SEL closeSel = sel_registerName("splashAdDidClose:closeType:");
    if ([bu respondsToSelector:closeSel]) {
        ((void (*)(id, SEL, id, long))objc_msgSend)(bu, closeSel, ad, 0);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *window = gSplashWindow;
        if (window && !window.hidden) {
            window.hidden = YES;
        }
    });
}

static void (*xc_origLoadSuccess)(id, SEL, id);
static void xc_loadSuccess(id self, SEL cmd, id ad) {
    gSplashBU = self;
    gSplashAd = ad;
    gSplashClosed = NO;
    if (xc_origLoadSuccess) xc_origLoadSuccess(self, cmd, ad);
}

static void (*xc_origWillShow)(id, SEL, id);
static void xc_willShow(id self, SEL cmd, id ad) {
    if (ad) gSplashAd = ad;
    if (xc_origWillShow) xc_origWillShow(self, cmd, ad);

    id bu = self;
    id adRef = ad;
    dispatch_async(dispatch_get_main_queue(), ^{
        XCFinishSplash(bu, adRef);
    });
}

static __attribute__((constructor)) void XCInstallAdSplashHooks(void) {
    Class cls = objc_getClass("_TtC9XiaoCanAd10AdSplashBU");
    if (!cls) return;

    Method loadM = class_getInstanceMethod(cls, sel_registerName("splashAdLoadSuccess:"));
    if (loadM) {
        xc_origLoadSuccess = (void (*)(id, SEL, id))method_setImplementation(loadM, (IMP)xc_loadSuccess);
    }
    Method showM = class_getInstanceMethod(cls, sel_registerName("splashAdWillShow:"));
    if (showM) {
        xc_origWillShow = (void (*)(id, SEL, id))method_setImplementation(showM, (IMP)xc_willShow);
    }
}

%hook UIWindow

- (void)makeKeyAndVisible {
    if (XCIsSplashAdWindow(self)) {
        gSplashWindow = self;
        self.alpha = 0.0;
        %orig;
        XCScheduleSkipTaps(self);
        XCKeepInvisible(self);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            XCFinishSplash(gSplashBU, gSplashAd);
        });
        return;
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && XCIsSplashAdWindow(self)) {
        gSplashWindow = self;
        self.alpha = 0.0;
        %orig;
        XCScheduleSkipTaps(self);
        XCKeepInvisible(self);
        return;
    }
    %orig;
}

%end

// GDT 开屏作为兜底路径保留。
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

    %orig;
}

%end
