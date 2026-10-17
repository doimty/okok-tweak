#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// OKOK (com.chipsea.btWeigh) 3.7.54
// 会员已验证；广告按广告位分层拦截，不碰 SDK 初始化。

static void OKOKMark(NSString *name) {
    NSString *path = [@"/var/mobile/Library/Caches" stringByAppendingPathComponent:name];
    [[NSString stringWithFormat:@"%@ pid=%d", [NSDate date], getpid()]
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void OKOKApplyVipUI(id self) {
    @try {
        UIView *noVip = [self valueForKey:@"kNoVipContentView"];
        UIView *vip = [self valueForKey:@"kVipContentView"];
        UILabel *timeLab = [self valueForKey:@"kVipTimeLab"];
        if ([noVip isKindOfClass:[UIView class]]) {
            [noVip setHidden:YES];
        }
        if ([vip isKindOfClass:[UIView class]]) {
            [vip setHidden:NO];
        }
        if ([timeLab isKindOfClass:[UILabel class]]) {
            [timeLab setText:@"2099-12-31 到期"];
        }
    } @catch (NSException *e) {
    }
}

%ctor {
    OKOKMark(@"okok_tweak_loaded.txt");
}

#pragma mark - 开屏广告：只拦展示

%hook OKKYSplashAdManager

- (void)showAdWithConfig {
    OKOKMark(@"okok_block_splash.txt");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ((void (*)(id, SEL))objc_msgSend)(self, @selector(closeAd));
    });
}

- (void)showAd_Taku {
    OKOKMark(@"okok_block_splash.txt");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ((void (*)(id, SEL))objc_msgSend)(self, @selector(closeAd));
    });
}

%end

#pragma mark - 广告位配置：直接回调空配置

%hook AdGainAdSettingManager

- (void)getAdSettingWithCodeId:(id)codeId completion:(id)completion {
    OKOKMark(@"okok_block_adconfig.txt");
    if (completion) {
        ((void (^)(id, id))completion)(nil, nil);
    }
}

- (void)getAdSettingWithCodeId:(id)codeId sHash:(id)sHash completion:(id)completion {
    OKOKMark(@"okok_block_adconfig.txt");
    if (completion) {
        ((void (^)(id, id))completion)(nil, nil);
    }
}

%end

#pragma mark - 摇一摇

%hook AdGainShakeHandler

- (void)start {}
- (void)startSensor {}
- (void)startWithPriority:(double)priority {}

%end

#pragma mark - 全屏 / 激励视频

%hook ShowFullScreenVideoAdManager

- (void)showAd_BUS {}
- (void)showAd_QQ {}

%end

%hook AdGainInterstitialAd

- (void)showAdFromViewController:(id)controller {}

%end

%hook AdGainRewardAd

- (void)showAdFromViewController:(id)controller {}

%end

#pragma mark - Banner / 原生广告

%hook AdGainBannerView

- (void)loadAd {}

%end

%hook AdGainNativeAd

- (void)loadAd {}

%end

#pragma mark - 会员业务层

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

%hook AppPayManager

- (BOOL)verifyVip {
    return YES;
}

%end

#pragma mark - 我的页面

%hook OKOKKYMyViewController2

- (BOOL)isVip {
    return YES;
}

- (NSString *)vipExpirationTime {
    return @"2099-12-31";
}

- (void)checkIfVip {
    %orig;
    OKOKApplyVipUI(self);
}

- (void)refreshUI {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setIsVip:), YES);
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setVipExpirationTime:), @"2099-12-31");
    %orig;
    OKOKApplyVipUI(self);
}

%end

#pragma mark - 会员页

%hook OKKYVIPVC

- (BOOL)isVip {
    return YES;
}

- (NSString *)expirationTime {
    return @"2099-12-31";
}

- (void)updateDataView {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setIsVip:), YES);
    %orig;
}

%end
