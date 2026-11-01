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
    /* 必须写 App 自己能写的目录：/var/mobile/Library/Caches 在沙盒外，
       App 进程写不进去，标记文件永远不出现（踩过）。 */
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
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
        /* UIApplication.windows 在 iOS 15 起标记弃用；本项目以 -Werror 编译，
           这里局部抑制，不改行为（实测该 API 返回的 window 正是我们要扫的那棵）。 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray<UIWindow *> *wins = [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
        for (UIWindow *w in wins) {
            OKOKSweepView(w, 0);
        }
    } @catch (NSException *e) {
    }
}

/* ================================================================== */
/* 事件驱动：广告视图一出现就处理（O(1)，不做树遍历）                  */
/* ================================================================== */
/*
 * 为什么需要：定时扫描（2..28s）之间的空档里，广告会先显示出来，
 * 等下一轮扫描才被收掉 —— 用户看到的就是"闪一下再消失"。
 * 这几个 hook 只在对应视图出现时触发一次，工作量是常数级，
 * 不会像启动期全树扫描那样把 launch 拖到看门狗时限。
 */

%hook ATBannerView

- (void)didMoveToSuperview {
    %orig;
    if (!OKOKVersionOK()) return;
    /* Logos 里 self 的类型是前向声明的 ATBannerView*，要转成 UIView* 才能调 UIKit */
    OKOKCollapseAdSlotAround((UIView *)self);
}

%end

%hook OKKYADHomeCell

- (void)didMoveToSuperview {
    %orig;
    if (!OKOKVersionOK()) return;
    UIView *cell = (UIView *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *parent = cell.superview;
        if (!parent) return;
        for (UIView *sib in [parent.subviews copy]) {
            if (sib == cell) continue;
            if ([NSStringFromClass([sib class]) isEqualToString:@"AutoScrollLableView"]) {
                OKOKRemoveFromFlow(sib);
            }
        }
        OKOKRemoveFromFlow(cell);
    });
}

%end

%hook OKKYFloatView

- (void)didMoveToSuperview {
    %orig;
    if (!OKOKVersionOK()) return;
    ((UIView *)self).hidden = YES;      /* 悬浮层，无布局副作用 */
}

%end
/* ================================================================== */
/* 开屏遮罩：只遮不拦                                                  */
/* ================================================================== */
/*
 * 前面六种"拦展示/调 closeAd"的做法全部失败（卡启动画面 / abort / 冻屏）。
 * 这里换一个完全不碰状态机的做法：广告自己的倒计时照常跑，
 * 只把盖在最上面的那层开屏容器设为不可见。
 *
 * 安全性：
 *   · 只在类名精确匹配到开屏 SDK 的视图时动作，匹配不到就什么都不做；
 *   · 从外部定时器轮询，不在视图自己的 -didMoveToSuperview 里改（会无限递归）；
 *   · 隐藏的是「最上层非 window 祖先」，避免只隐藏广告层导致底下仍是空屏。
 *
 * 注意：该做法尚未在"真的拉到广告"的一次启动里验证过 —— 开屏有频次限制，
 * 连续冷启动会一直不填充。若长时间观察仍未生效，说明命中的类名不对，
 * 需要重新在广告出现的那一刻抓一次类名。
 */

static BOOL kOKOKSplashHiddenOnce = NO;

static BOOL OKOKIsSplashClass(NSString *name) {
    return [name isEqualToString:@"ATNativeMixSplashView"]
        || [name isEqualToString:@"ATNativeSplashViewController"]
        || [name isEqualToString:@"ATNativeMixSplashContentView"];
}

/* 往上找到「最上层非 window 祖先」 */
static UIView *OKOKTopAncestorBelowWindow(UIView *v) {
    UIView *best = v;
    UIView *cur = v;
    for (int i = 0; i < 30; i++) {
        UIView *sv = cur.superview;
        if (!sv) break;
        NSString *n = NSStringFromClass([sv class]);
        if ([n isEqualToString:@"UIWindow"] || [n hasSuffix:@"Window"]) {
            break;
        }
        best = sv;
        cur = sv;
    }
    return best;
}

static void OKOKSplashScanOnce(void) {
    if (kOKOKSplashHiddenOnce) return;
    if (!OKOKVersionOK()) return;

    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray<UIWindow *> *wins = [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop

        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:wins];
        int guard = 0;

        while (stack.count && guard++ < 8000) {
            UIView *v = [stack lastObject];
            [stack removeLastObject];
            if (!v) continue;

            NSString *name = NSStringFromClass([v class]);
            if (OKOKIsSplashClass(name)) {
                UIView *top = OKOKTopAncestorBelowWindow(v);
                top.hidden = YES;
                v.hidden = YES;
                kOKOKSplashHiddenOnce = YES;
                return;
            }

            [stack addObjectsFromArray:v.subviews];
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
    /* 开屏遮罩：0.5s 起每 200ms 扫一次，最多 40 次（约 8.5 秒，覆盖广告出现窗口） */
    for (int i = 0; i < 40; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)((0.5 + i * 0.2) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            OKOKSplashScanOnce();
        });
    }

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
