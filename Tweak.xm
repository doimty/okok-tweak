#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// OKOK (com.chipsea.btWeigh) 3.7.54
// 目标：跳过广告加载/展示，本地解锁会员状态。
// 仅覆盖已从 Mach-O 中确认存在的方法，未确认的方法不 hook。

#pragma mark - 开屏广告

%hook OKKYSplashAdManager

- (void)initAllAD {}
- (void)initTakuSDK {}
- (void)startLoadShowAd:(BOOL)show {}
- (void)loadShowAd {}
- (void)showAdWithConfig {}
- (void)showAd_Taku {}

%end

#pragma mark - 全屏视频 / 激励视频

%hook ShowFullScreenVideoAdManager

- (void)loadVedio {}
- (void)showAd_BUS {}
- (void)showAd_QQ {}

%end

#pragma mark - AdGain 聚合广告

%hook AdGainInterstitialAd

- (void)loadAd {}
- (void)showAdFromViewController:(id)controller {}

%end

%hook AdGainRewardAd

- (void)loadAd {}
- (void)showAdFromViewController:(id)controller {}

%end

%hook AdGainNativeAd

- (void)loadAd {}

%end

%hook AdGainSplashAdViewController

- (void)configre {}

%end

#pragma mark - 会员状态

%hook VIPBusiness

- (BOOL)isVip {
    return YES;
}

%end

%hook ScaleAccessBusiness

- (BOOL)isVip {
    return YES;
}

%end

%hook OKKYVIPVC

- (BOOL)isVip {
    return YES;
}

%end

%hook OKOKKYMyViewController2

- (BOOL)isVip {
    return YES;
}

%end

%hook AppPayManager

- (BOOL)verifyVip {
    return YES;
}

%end
