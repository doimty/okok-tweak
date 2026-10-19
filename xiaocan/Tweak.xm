#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 小蚕 3.21.x 广告来自内置的 RichmobAdSDK（Swift 类，ObjC 可见）。
// 关掉开屏 / 插屏 / 信息流；激励视频保留（用户主动触发）。

static void XCNoop(id self, SEL _cmd) {}

static void XCHookMethod(Class cls, const char *selName) {
    if (!cls) return;
    SEL sel = sel_registerName(selName);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) method_setImplementation(m, (IMP)XCNoop);
}

// 摇一摇跳转：广告 SDK 用 CMMotionManager 读加速度，直接停掉
%hook CMMotionManager

- (void)startAccelerometerUpdates {}
- (void)startAccelerometerUpdatesToQueue:(id)queue withHandler:(id)handler {}
- (void)startDeviceMotionUpdates {}
- (void)startDeviceMotionUpdatesToQueue:(id)queue withHandler:(id)handler {}
- (void)startDeviceMotionUpdatesUsingReferenceFrame:(NSUInteger)frame toQueue:(id)queue withHandler:(id)handler {}

%end

// Flutter 信息流广告的原生视图
%hook FlutterNativeAdView

- (void)loadAd {}
- (void)showAd {}

%end

%ctor {
    Class splash = objc_getClass("RichmobAdSDK.RichmobSplashAdManger");
    if (splash) {
        XCHookMethod(splash, "loadAdDataWithAdId:");
        XCHookMethod(splash, "loadAdDataWithBidToken:");
        XCHookMethod(splash, "showAdInControllerWithViewController:");
        XCHookMethod(splash, "showAdInWindowWithWindow:");
    }

    Class insert = objc_getClass("RichmobAdSDK.RichmobInsertScreenAdManger");
    if (insert) {
        XCHookMethod(insert, "loadAdDataWithAdId:");
        XCHookMethod(insert, "loadAdDataWithBidToken:");
        XCHookMethod(insert, "showAdInControllerWithViewController:");
    }

    Class native = objc_getClass("RichmobAdSDK.RichmobNativeAdManger");
    if (native) {
        XCHookMethod(native, "loadAdDataWithAdId:");
        XCHookMethod(native, "loadAdDataWithBidToken:");
    }
}
