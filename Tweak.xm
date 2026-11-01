#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

/*
 * OKOK (com.chipsea.btWeigh) 3.7.54
 *
 * ===================================================================
 * 合并版 v3 —— 关键改动：从「启动期逐视图 hook」改为「启动后一次性扫描」
 * ===================================================================
 *
 * 为什么改（都是真机打出来的）：
 *
 *   · 前两版把处理逻辑挂在 -didMoveToSuperview 上，等于在启动过程中
 *     不停做视图扫描 + 改约束。实测结果是被看门狗 SIGKILL，连崩溃报告
 *     都不留（procLaunch 到 exit 只有几百毫秒～数秒）。
 *
 *   · 而在 App 跑起来之后、用交互方式做同样的操作 —— 完全没问题，
 *     已经用截图逐项验证过（首页四处、体测报告页）。
 *
 *   · 所以正确姿势是：不要在启动路径上干活，等启动完了一次性扫。
 *     本文件用 %ctor + 延迟扫描实现，逻辑与已验证的手动操作一一对应。
 *
 * -------------------------------------------------------------------
 * 三条实测规矩（改代码前先读）
 * -------------------------------------------------------------------
 *  ① 只压高度不够：clipsToBounds 默认 NO，高度归零后子视图仍溢出渲染
 *     → 必须配 hidden。
 *  ② 只压高度也不够消空白：Masonry 链每个节点带 +13
 *     → 还要把「引用自己的下一条 top」归零；但不要动自己的 top，否则贴死。
 *  ③ 第三方 SDK 容器（ATBannerView）自身是 NSContentSizeLayoutConstraint，
 *     改 constant 会被重算 → 必须收它外面那层 App 广告槽。
 *  ④ 不要在启动路径上做布局操作；也不要调 layoutIfNeeded。
 *
 * -------------------------------------------------------------------
 * 会员段为仓库原有代码，本次未修改、未验证。
 * -------------------------------------------------------------------
 */

/* ================================================================== */
/* 原仓库既有：标记与会员 UI 工具（未改动）                            */
/* ================================================================== */

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

/* ================================================================== */
/* 门控 + 约束工具                                                      */
/* ================================================================== */

static NSString *const kOKOKBundleID = @"com.chipsea.btWeigh";
static NSString *const kOKOKKnownVersion = @"3.7.54";

static BOOL OKOKVersionOK(void) {
    static BOOL ok = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        ok = [info[@"CFBundleIdentifier"] isEqualToString:kOKOKBundleID] &&
             [info[@"CFBundleShortVersionString"] isEqualToString:kOKOKKnownVersion];
    });
    return ok;
}

/* 高度约束归零（约束可能在自己身上，也可能在父视图上） */
static void OKOKZeroHeight(UIView *v) {
    if (!v) return;
    for (NSLayoutConstraint *c in v.constraints) {
        if (c.firstItem == v && c.firstAttribute == NSLayoutAttributeHeight) {
            c.constant = 0;
        }
    }
    UIView *p = v.superview;
    if (p) {
        for (NSLayoutConstraint *c in p.constraints) {
            if (c.firstItem == v && c.firstAttribute == NSLayoutAttributeHeight) {
                if ([NSStringFromClass([c class]) containsString:@"ContentSize"]) continue;
                c.constant = 0;
            }
        }
    }
}

/* 把「引用 v 的下一条 top 约束」归零；刻意不动 v 自己的 top */
static void OKOKZeroNextTop(UIView *v) {
    UIView *p = v.superview;
    if (!v || !p) return;
    for (NSLayoutConstraint *c in p.constraints) {
        if (c.secondItem == v && c.firstAttribute == NSLayoutAttributeTop) {
            c.constant = 0;
        }
    }
}

/* 完整移除：压高度 + 隐藏 + 下一条 top 归零。不做任何强制布局。 */
static void OKOKRemoveFromFlow(UIView *v) {
    if (![v isKindOfClass:[UIView class]]) return;

    OKOKZeroHeight(v);
    v.hidden = YES;
    OKOKZeroNextTop(v);

    [v setNeedsLayout];
    [v.superview setNeedsLayout];
}

/* 收掉第三方广告容器外面那层 App 广告槽 */
static void OKOKCollapseAdSlotAround(UIView *adView) {
    if (!adView) return;
    UIView *slot = adView.superview;
    if (!slot) return;

    CGFloat h = CGRectGetHeight(slot.bounds);
    if (h <= 0 || h > 120) return;

    for (NSLayoutConstraint *c in slot.constraints) {
        if (c.firstItem == slot && c.firstAttribute == NSLayoutAttributeHeight) {
            c.constant = 0;
        }
    }
    slot.hidden = YES;
    [slot setNeedsLayout];
    [slot.superview setNeedsLayout];
}

/* ================================================================== */
/* 一次性扫描：逻辑与已验证的手动操作一一对应                          */
/* ================================================================== */

static BOOL OKOKIsClass(UIView *v, NSString *name) {
    return [NSStringFromClass([v class]) isEqualToString:name];
}

static void OKOKSweepView(UIView *v, int depth);

static void OKOKSweepOne(UIView *v) {
    if (!v) return;
    Class cls = [v class];
    NSString *name = NSStringFromClass(cls);

    if ([name isEqualToString:@"OKKYADHomeCell"]) {
        OKOKRemoveFromFlow(v);
        return;
    }

    if ([name isEqualToString:@"AutoScrollLableView"]) {
        /* 只有在「同父视图里存在广告 cell」时才处理 —— 这个组件别处也在用 */
        UIView *parent = v.superview;
        if (!parent) return;
        BOOL hasAdCell = NO;
        for (UIView *sib in parent.subviews) {
            if (sib == v) continue;
            if (OKOKIsClass(sib, @"OKKYADHomeCell")) { hasAdCell = YES; break; }
        }
        if (!hasAdCell) return;
        OKOKRemoveFromFlow(v);
        return;
    }

    if ([name isEqualToString:@"OKKYFloatView"]) {
        /* 注意：绝不能顺带处理 OKKYFloatView2 —— 那是左下角「聊天」按钮 */
        v.hidden = YES;
        return;
    }

    if ([name isEqualToString:@"ATBannerView"]) {
        OKOKCollapseAdSlotAround(v);
        return;
    }
}

static void OKOKSweepView(UIView *v, int depth) {
    if (!v || depth > 40) return;
    /* 自底向上：先处理子视图，避免处理父视图后子视图被摘掉找不到 */
    NSArray *subs = [v.subviews copy];
    for (UIView *s in subs) {
        OKOKSweepView(s, depth + 1);
    }
    OKOKSweepOne(v);
}

static void OKOKSweepAll(void) {
    if (!OKOKVersionOK()) return;
    @try {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            OKOKSweepView(w, 0);
        }
    } @catch (NSException *e) {
    }
}

/* ================================================================== */
/* 调度：启动后再扫，避开启动路径                                      */
/* ================================================================== */

%ctor {
    OKOKMark(@"okok_tweak_loaded.txt");

    /* 不在启动路径上干活。
       实测这台设备从冷启动到首页可用约 9-10 秒，所以只扫 2.5s/6s 会全部落空。
       改成多轮，覆盖首页建好之后；每轮只是一次视图树遍历，开销很小。 */
    static const int64_t kOKOKSweepAt[] = {2, 4, 6, 8, 10, 12, 14, 16, 18, 21, 24, 28};
    for (int i = 0; i < (int)(sizeof(kOKOKSweepAt) / sizeof(kOKOKSweepAt[0])); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kOKOKSweepAt[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            OKOKSweepAll();
        });
    }
}

/* ================================================================== */
/* 开屏广告 —— 原仓库方案已停用，且暂无可用替代                        */
/* ================================================================== */
/*
 * 原实现（已移除）：
 *   %hook OKKYSplashAdManager showAdWithConfig / showAd_Taku → 0.35s 后 closeAd
 *
 * 为什么移除（四条路径全部真机验证失败）：
 *   1. 不调 %orig（等于不展示）+ 随后 closeAd → abort，App 卡启动画面
 *   2. 展示后 150ms 调 closeAd → abort（展示中途不能关）
 *   3. 展示后 800ms 调 closeAd → 广告冻屏、倒计时卡住、App 被永久挡死
 *   4. 强制 -startLoadShowAd:NO → 卡启动画面（该参数确为"是否展示"，原值 0x1）
 *   5. 隐藏 UIWindow(windowLevel>=1500) → 不适用：全程只有一次 level=0 的
 *      makeKeyAndVisible，广告窗口根本不用这个方法
 *   6. 隐藏 ATNativeMixSplashView → didMoveToSuperview 无限递归（已崩过，
 *      165ms 内触发 46 次）
 *
 * 结论：App 的启动门无条件等开屏流程自然走完。任何干预都会挂死或冻屏。
 *       当前版本不处理开屏，等有更低层的切入点再说。
 */

/* ================================================================== */
/* 广告位配置（原仓库逻辑，保留）                                      */
/* 注：实测首页刷新时这两个方法 0 命中，只影响启动期配置下发           */
/* ================================================================== */

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

/* ================================================================== */
/* 摇一摇（原仓库逻辑，保留，未单独验证）                              */
/* ================================================================== */

%hook AdGainShakeHandler

- (void)start {}
- (void)startSensor {}
- (void)startWithPriority:(double)priority {}

%end

/* ================================================================== */
/* 全屏 / 插屏 / 激励（原仓库逻辑，保留，未单独验证）                  */
/* ================================================================== */

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

/* ================================================================== */
/* Banner / 原生广告（原仓库逻辑，保留，未单独验证）                  */
/* ================================================================== */

%hook AdGainBannerView

- (void)loadAd {}

%end

%hook AdGainNativeAd

- (void)loadAd {}

%end

/* ================================================================== */
/* 会员段 —— 仓库原有代码，本次原样保留，未做任何修改与验证            */
/* ================================================================== */

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

/* ================================================================== */
/* 未覆盖（记录在案）                                                  */
/* ================================================================== */
/*
 * 开屏广告：见上方说明，六条路径全部失败。
 *
 * 首页「这些食谱减肥有点厉害哦～」推广条：
 *   位于 OKOKKYDeitSportCaloriesCell 内部，无语义类名的匿名 UIView
 *   （UIView > UIImageView 预渲染整图 + UIButton），实测位置 (20,128,356x64)。
 *   需从 -[OKOKKYDeitSportCaloriesCell gotoRecipeDatailVC] 反推容器。
 *
 * 首页「点击去【绑定设备】」：功能提示，不是广告，保留。
 *
 * 扫描时机：2.5s / 6s 各一次。如果首页是异步刷新后才出现推广位，
 * 可能需要在此基础上再加一次按事件触发的扫描（例如首页 VC 的 viewDidAppear）。
 */
