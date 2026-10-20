#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import "XCLaunchPolicy.h"

// Preserve SDK presentation state, but keep known high-level splash windows clear.
// 1.0.9 selects LaunchUtil's native ignoreSplashAd branch at initialization.
// It does not call HomeSplashPopupGate or invoke raw Swift function addresses.
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

static Class gLaunchUtilClass;
static ptrdiff_t gIgnoreSplashOffset;
static ptrdiff_t gLaunchViewOffset;

static void XCEnableNativeLaunchSkip(id instance) {
    if (!instance || object_getClass(instance) != gLaunchUtilClass) return;
    BOOL applied = XCSetNativeSplashIgnore((__bridge void *)instance,
                                          class_getInstanceSize(gLaunchUtilClass),
                                          gIgnoreSplashOffset, gLaunchViewOffset);
    NSLog(@"[XiaocanAdFree 1.0.9] LaunchUtil native ignore %@",
          applied ? @"applied" : @"rejected");
}

// Use only the App's real instance, after its initializer has cleared fields.
%group XCNativeLaunchSkip
%hook XCLaunchUtil

- (id)init {
    id instance = %orig;
    XCEnableNativeLaunchSkip(instance);
    return instance;
}

%end
%end

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

%ctor {
    @autoreleasepool {
        %init;
        NSBundle *app = [NSBundle mainBundle];
        BOOL knownApp = [app.bundleIdentifier isEqualToString:@"com.realtech.xiaocan"] &&
            [[app objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"3.21.6"];
        Class cls = objc_getClass("_TtC7xiaocan10LaunchUtil");
        Ivar flag = cls ? class_getInstanceVariable(cls, "ignoreSplashAd") : NULL;
        Ivar view = cls ? class_getInstanceVariable(cls, "$__lazy_storage_$_launchView") : NULL;
        BOOL knownLayout = cls && flag && view && class_getInstanceSize(cls) == 24 &&
            ivar_getOffset(flag) == 8 && ivar_getOffset(view) == 16;
        if (knownApp && knownLayout) {
            gLaunchUtilClass = cls;
            gIgnoreSplashOffset = ivar_getOffset(flag);
            gLaunchViewOffset = ivar_getOffset(view);
            %init(XCNativeLaunchSkip, XCLaunchUtil = cls);
            NSLog(@"[XiaocanAdFree 1.0.9] native launch hook ready, awaiting real init");
        } else {
            NSLog(@"[XiaocanAdFree 1.0.9] native launch skip disabled: version/layout mismatch");
        }
    }
}
