#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// 小蚕 3.21.6 的开屏 SDK 会轮换；已观察到的开屏都使用约 2001 层窗口。
// 持续将该窗口透明化，但保留原显示调用，让 SDK 自身状态机继续运行。
// App 级 HomeSplashPopupGate 是实验性统一结束入口，只在真实高层开屏窗口存在时调用。
// BU/GDT 仍保留各自已经实测过的关闭回调。
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

static __weak id gSplashBU;
static __weak id gSplashAd;
static __weak UIWindow *gSplashWindow;
static BOOL gSplashClosed;

static void XCFinishSplash(id bu, id ad) {
    if (gSplashClosed) return;
    if (!bu) bu = gSplashBU;
    if (!ad) ad = gSplashAd;
    if (!bu || !ad) return;

    SEL closeSel = sel_registerName("splashAdDidClose:closeType:");
    if (![bu respondsToSelector:closeSel]) return;

    gSplashClosed = YES;
    ((void (*)(id, SEL, id, long))objc_msgSend)(bu, closeSel, ad, 0);

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

static __weak id gHomeSplashGate;
static BOOL gHomeGateCalled;

static BOOL XCHasSplashWindow(void) {
    if (gSplashWindow && XCIsSplashAdWindow(gSplashWindow)) return YES;

    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (XCIsSplashAdWindow(window)) return YES;
        }
    }
    return NO;
}

static void XCInvokeHomeSplashGate(id gate) {
    if (!gate || gHomeGateCalled || gSplashBU || !XCHasSplashWindow()) return;

    SEL selector = sel_registerName("handleAdClosed");
    if (![gate respondsToSelector:selector]) return;

    gHomeGateCalled = YES;
    ((void (*)(id, SEL))objc_msgSend)(gate, selector);
}

static id (*xc_origGateInit)(id, SEL);
static id xc_gateInit(id self, SEL cmd) {
    id gate = xc_origGateInit ? xc_origGateInit(self, cmd) : self;
    if (gate) {
        gHomeSplashGate = gate;
        dispatch_async(dispatch_get_main_queue(), ^{
            XCInvokeHomeSplashGate(gate);
        });
    }
    return gate;
}

static __attribute__((constructor)) void XCInstallAdSplashHooks(void) {
    Class cls = objc_getClass("_TtC9XiaoCanAd10AdSplashBU");
    if (cls) {
        Method loadM = class_getInstanceMethod(cls, sel_registerName("splashAdLoadSuccess:"));
        if (loadM) {
            xc_origLoadSuccess = (void (*)(id, SEL, id))method_setImplementation(loadM, (IMP)xc_loadSuccess);
        }
        Method showM = class_getInstanceMethod(cls, sel_registerName("splashAdWillShow:"));
        if (showM) {
            xc_origWillShow = (void (*)(id, SEL, id))method_setImplementation(showM, (IMP)xc_willShow);
        }
    }

    Class gateClass = objc_getClass("_TtC7xiaocanP33_02340CA986B901ABAA966A8072314D0519HomeSplashPopupGate");
    Method gateInit = gateClass ? class_getInstanceMethod(gateClass, sel_registerName("init")) : NULL;
    if (gateInit) {
        xc_origGateInit = (id (*)(id, SEL))method_setImplementation(gateInit, (IMP)xc_gateInit);
    }
}

%hook UIWindow

- (void)setAlpha:(CGFloat)alpha {
    if (XCIsSplashAdWindow(self)) {
        %orig(0.0);
        return;
    }
    %orig;
}

- (void)setWindowLevel:(UIWindowLevel)windowLevel {
    %orig;
    if (XCIsSplashAdWindow(self)) {
        gSplashWindow = self;
        self.userInteractionEnabled = NO;
        self.alpha = 0.0;
    }
}

- (void)makeKeyAndVisible {
    if (XCIsSplashAdWindow(self)) {
        gSplashWindow = self;
        self.userInteractionEnabled = NO;
        self.alpha = 0.0;
        %orig;
        self.alpha = 0.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            XCInvokeHomeSplashGate(gHomeSplashGate);
        });
        return;
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && XCIsSplashAdWindow(self)) {
        gSplashWindow = self;
        self.userInteractionEnabled = NO;
        self.alpha = 0.0;
        %orig;
        self.alpha = 0.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            XCInvokeHomeSplashGate(gHomeSplashGate);
        });
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
