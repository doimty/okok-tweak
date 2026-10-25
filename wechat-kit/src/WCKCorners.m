#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKSVGPalette.h"
#import <math.h>

// WCR evidence: MMTableViewCell.setFrame:/layoutSubviews and the dedicated
// NewMainFrameCell.setFrame: path. This is an independent, page-scoped repair,
// not WCR's entire renderer. Never hook UIView or alter a control's background.
static char sCornerStateKey;
static NSHashTable<UITableViewCell *> *sCornerCells; // weak, main-thread only
static _Thread_local NSUInteger sCornerFrameDepth, sCornerLayoutDepth, sCornerReuseDepth;
static _Thread_local __unsafe_unretained UITableViewCell *sCornerFrameCell;
static _Thread_local __unsafe_unretained UITableViewCell *sCornerLayoutCell;
static _Thread_local __unsafe_unretained UITableViewCell *sCornerReuseCell;
static _Thread_local __unsafe_unretained UITableViewCell *sCornerInternalFrameCell;
static BOOL sCornerRefreshQueued;

@interface WCKCornerLayerState : NSObject
@property(nonatomic, weak) CALayer *layer;
@property(nonatomic) CGFloat radius, lastRadius, width, lastWidth;
@property(nonatomic) NSUInteger mask, lastMask;
@property(nonatomic, copy) NSString *curve, *lastCurve;
@property(nonatomic) BOOL ownsGeometry, ownsBorder;
@property(nonatomic, strong) UIColor *color, *lastColor;
@end
@implementation WCKCornerLayerState @end

@interface WCKCornerState : NSObject
@property(nonatomic, weak) UITableView *table;
@property(nonatomic, weak) UIView *superview;
@property(nonatomic) CGRect hostFrame, appliedFrame;
@property(nonatomic) BOOL ownsFrame, ownsFill, ownsViewFill;
@property(nonatomic, strong) UIColor *hostFill, *appliedFill;
@property(nonatomic, strong) UIColor *hostViewFill, *appliedViewFill;
@property(nonatomic, strong) NSMutableArray<WCKCornerLayerState *> *layers;
@end
@implementation WCKCornerState @end

typedef void (*WCKCornerFrameIMP)(id, SEL, CGRect);
typedef void (*WCKCornerVoidIMP)(id, SEL);
static WCKCornerFrameIMP sMMFrame, sMainFrame;
static WCKCornerVoidIMP sMMLayout, sMainLayout, sMMReuse, sMainReuse;
static const NSUInteger WCKCornerRefreshLimit = 512;

static BOOL WCKCornerObjectsEqual(id a, id b) { return a == b || [a isEqual:b]; }
static BOOL WCKCornerColorsEqual(CGColorRef a, CGColorRef b) {
    return a == b || (a && b && CGColorEqualToColor(a, b));
}
static BOOL WCKCornerFiniteRect(CGRect r) {
    return isfinite(r.origin.x) && isfinite(r.origin.y) && isfinite(r.size.width) &&
        isfinite(r.size.height) && r.size.width > 0 && r.size.height > 0;
}
static double WCKCornerNumber(NSDictionary *snapshot, NSString *key, double fallback,
                              double high) {
    id value = snapshot[key];
    double x = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    return isfinite(x) ? MIN(high, MAX(0.0, x)) : fallback;
}
static UIColor *WCKCornerFill(NSDictionary *snapshot, NSString *key) {
    id text = snapshot[key]; uint32_t rgb = 0;
    if (![text isKindOfClass:NSString.class] || !WCKHexToRGB(text, &rgb)) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
        green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
static WCKCornerState *WCKCornerGetState(UITableViewCell *cell, BOOL create) {
    WCKCornerState *state = objc_getAssociatedObject(cell, &sCornerStateKey);
    if (!state && create) {
        state = [WCKCornerState new]; state.layers = [NSMutableArray new];
        objc_setAssociatedObject(cell, &sCornerStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
static UITableView *WCKCornerTable(UITableViewCell *cell) {
    UIView *parent = cell.superview;
    for (NSUInteger depth = 0; parent && depth < 24; ++depth, parent = parent.superview)
        if ([parent isKindOfClass:UITableView.class]) return (UITableView *)parent;
    return nil;
}
static UIViewController *WCKCornerOwner(UITableView *table) {
    UIResponder *next = table;
    for (NSUInteger depth = 0; next && depth < 64; ++depth, next = next.nextResponder)
        if ([next isKindOfClass:UIViewController.class]) return (UIViewController *)next;
    return nil;
}
static NSString *WCKCornerPageKey(UIViewController *owner) {
    static NSArray<NSString *> *names;
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"NewMainFrameViewController", @"ContactsViewController",
                  @"FindFriendEntryViewController", @"MoreViewController",
                  @"ContactInfoViewController"];
        keys = @[@"mainFrameCornerEnabled", @"homepageCornerEnabled",
                 @"discoverPageCornerEnabled", @"myPageCornerEnabled",
                 @"friendProfileCornerEnabled", @"tpModeCornerEnabled"];
    });
    for (NSUInteger i = 0; i < names.count; ++i) {
        Class cls = NSClassFromString(names[i]);
        if (cls && [owner isKindOfClass:cls]) return keys[i];
    }
    return nil;
}
static BOOL WCKCornerPageEnabled(UIViewController *owner, NSDictionary *snapshot) {
    NSString *key = WCKCornerPageKey(owner);
    if (!key) return NO;
    return [snapshot[key] boolValue];
}
// ---- generic view corners: menus, search fields and other painted containers

static const BOOL WCKEnableUnverifiedComponentFamilies = NO;
static void (*sViewDidMoveToWindow)(id, SEL);
static void (*sViewSetBackgroundColor)(id, SEL, UIColor *);
static void (*sViewLayoutSubviews)(id, SEL);
static void (*sAvatarLayoutSubviews)(id, SEL);
static void (*sProfileAvatarLayoutSubviews)(id, SEL);
static void (*sFakeAvatarLayoutSubviews)(id, SEL);
static void (*sMsgNavBarLayoutSubviews)(id, SEL);
static void (*sNewMsgNavBarLayoutSubviews)(id, SEL);
static void (*sTabBarLayoutSubviews)(id, SEL);
static char sCornerViewMarkerKey;
static char sVerifiedLayerStateKey;

static BOOL WCKCornerNameHas(UIView *view, NSString *needle, NSUInteger depth) {
    UIView *current = view;
    for (NSUInteger i = 0; current && i <= depth; ++i, current = current.superview)
        if ([NSStringFromClass(current.class) rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}
static NSString *WCKCornerFamilyForView(UIView *view) {
    // Specific WCR-like paths win over generic class-name fallbacks.
    if (WCKCornerNameHas(view, @"Search", 4) || WCKCornerNameHas(view, @"FTS", 2)) return @"searchCorner";
    if (WCKCornerNameHas(view, @"Keyboard", 3) || WCKCornerNameHas(view, @"InputSet", 3)) return @"imeKeyboardCorner";
    if (WCKCornerNameHas(view, @"PlusMenu", 4) || WCKCornerNameHas(view, @"AddMenu", 4)) return @"plusMenuCorner";
    if (WCKCornerNameHas(view, @"SwipeMenu", 4) || WCKCornerNameHas(view, @"ContextualAction", 4)) return @"mainFrameSwipeMenuCorner";
    if (WCKCornerNameHas(view, @"ActionSheet", 4) || WCKCornerNameHas(view, @"Menu", 3) ||
        WCKCornerNameHas(view, @"Popover", 3)) return @"menuCorner";
    if (WCKCornerNameHas(view, @"Alert", 4) || WCKCornerNameHas(view, @"Popup", 4)) return @"systemPopupCorner";
    if (WCKCornerNameHas(view, @"ChatToolbar", 4)) return @"chatToolbarCorner";
    if (WCKCornerNameHas(view, @"Toolbar", 3)) return @"toolbarCorner";
    if (WCKCornerNameHas(view, @"Topbar", 3) || WCKCornerNameHas(view, @"NavigationBar", 3)) return @"topbarCorner";
    if (WCKCornerNameHas(view, @"Emoji", 3) || WCKCornerNameHas(view, @"Emoticon", 3)) return @"emojiCorner";
    if (WCKCornerNameHas(view, @"SystemMessage", 4)) return @"systemMessageCorner";
    if (WCKCornerNameHas(view, @"Notice", 4)) return @"systemNoticeCorner";
    if (WCKCornerNameHas(view, @"Bubble", 4)) return @"chatBubbleCorner";
    if (WCKCornerNameHas(view, @"ImageMessage", 4) || WCKCornerNameHas(view, @"ImageContent", 4)) return @"chatImageCorner";
    if (WCKCornerNameHas(view, @"FileMessage", 4) || WCKCornerNameHas(view, @"FileContent", 4)) return @"chatFileCorner";
    if (WCKCornerNameHas(view, @"Location", 4)) return @"chatLocationCorner";
    if (WCKCornerNameHas(view, @"Time", 4)) return @"chatTimeRoundCorner";
    if (WCKCornerNameHas(view, @"Refer", 4) || WCKCornerNameHas(view, @"Quote", 4)) return @"msgReferCorner";
    if (WCKCornerNameHas(view, @"VoiceTranslate", 4) || WCKCornerNameHas(view, @"Translate", 4)) return @"voiceTranslateCorner";
    if (WCKCornerNameHas(view, @"Finder", 4)) return @"finderCorner";
    if (WCKCornerNameHas(view, @"Service", 4) || WCKCornerNameHas(view, @"Brand", 4)) return @"serviceCorner";
    if (WCKCornerNameHas(view, @"Moment", 4) || WCKCornerNameHas(view, @"Sns", 4)) return @"momentCorner";
    if (WCKCornerNameHas(view, @"Avatar", 4) || WCKCornerNameHas(view, @"HeadImage", 4)) return @"avatarCorner";
    if (WCKCornerNameHas(view, @"Profile", 4) || WCKCornerNameHas(view, @"ContactInfo", 4)) return @"profileCorner";
    if (WCKCornerNameHas(view, @"Send", 4) || WCKCornerNameHas(view, @"Publish", 4)) return @"sendPublishButtonCorner";
    return @"otherCorner";
}
static BOOL WCKCornerViewExcluded(UIView *view) {
    Class cls = view.class;
    NSString *family = WCKCornerFamilyForView(view);
    for (NSString *name in @[@"UILabel", @"UIVisualEffectView", @"UIScrollView",
                             @"UITableView", @"UICollectionView", @"UIWebView", @"WKWebView",
                             @"UIWindow", @"UIPickerView", @"UIDatePicker", @"UIActivityIndicatorView",
                             @"UIProgressView", @"UISwitch", @"UISlider", @"UISegmentedControl"]) {
        Class excluded = NSClassFromString(name);
        if (excluded && [cls isSubclassOfClass:excluded]) return YES;
    }
    Class imageView = NSClassFromString(@"UIImageView");
    if (imageView && [cls isSubclassOfClass:imageView] &&
        ![family isEqualToString:@"avatarCorner"] && ![family isEqualToString:@"chatImageCorner"]) return YES;
    // Text fields/text views are eligible only when their own path is input/search.
    Class textField = NSClassFromString(@"UITextField");
    Class textView = NSClassFromString(@"UITextView");
    if ((textField && [cls isSubclassOfClass:textField]) || (textView && [cls isSubclassOfClass:textView])) {
        if (![family isEqualToString:@"inputCorner"] && ![family isEqualToString:@"searchCorner"]) return YES;
    }
    if (([NSStringFromClass(cls) hasPrefix:@"UIInputSet"] || [NSStringFromClass(cls) hasPrefix:@"UIInputView"]) &&
        ![family isEqualToString:@"imeKeyboardCorner"]) return YES;
    return [NSStringFromClass(cls) hasPrefix:@"WCK"];
}
static BOOL WCKCornerViewPaints(UIView *view, NSString *family) {
    UIColor *colour = view.backgroundColor;
    if (!colour) {
        if (![family isEqualToString:@"avatarCorner"] && ![family isEqualToString:@"chatImageCorner"]) return NO;
        if (![view respondsToSelector:@selector(image)]) return NO;
        @try { return [view valueForKey:@"image"] != nil; } @catch (__unused NSException *exception) { return NO; }
    }
    CGFloat alpha = 1;
    if (![colour getWhite:NULL alpha:&alpha] && ![colour getRed:NULL green:NULL blue:NULL alpha:&alpha]) return NO;
    return alpha > 0.01;
}
static void WCKCornerClearView(UIView *view) {
    NSDictionary *saved = objc_getAssociatedObject(view, &sCornerViewMarkerKey);
    if (![saved isKindOfClass:NSDictionary.class]) return;
    if (view.layer.cornerRadius == [saved[@"radius"] doubleValue])
        view.layer.cornerRadius = [saved[@"hostRadius"] doubleValue];
    if (view.layer.masksToBounds == [saved[@"appliedMasks"] boolValue])
        view.layer.masksToBounds = [saved[@"hostMasks"] boolValue];
    if (WCKCornerObjectsEqual(view.layer.cornerCurve, saved[@"appliedCurve"]))
        view.layer.cornerCurve = saved[@"hostCurve"];
    objc_setAssociatedObject(view, &sCornerViewMarkerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void WCKCornerApplyToView(UIView *view) {
    if (!NSThread.isMainThread || ![view isKindOfClass:UIView.class]) return;
    NSDictionary *snapshot = WCKSettings.shared.snapshot;
    if (!WCKEnabled(@"corners") || WCKCornerViewExcluded(view) ||
        [view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class] ||
        view.window == nil || view.hidden || view.alpha < 0.01) { WCKCornerClearView(view); return; }
    NSString *family = WCKCornerFamilyForView(view);
    BOOL enabled = [snapshot[[family stringByAppendingString:@"Enabled"]] boolValue];
    // The reverse-engineered source proves most WCR keys exist, but does not
    // prove their WeChat host binding. Keep speculative UIView classification
    // opt-in until a host anchor or runtime A/B confirms it.
    if (!WCKEnableUnverifiedComponentFamilies &&
        ![family isEqualToString:@"avatarCorner"] &&
        ![family isEqualToString:@"chatImageCorner"]) enabled = NO;
    NSMutableDictionary *saved = [objc_getAssociatedObject(view, &sCornerViewMarkerKey) mutableCopy];
    if (saved && (view.layer.cornerRadius != [saved[@"radius"] doubleValue] ||
                  view.layer.masksToBounds != [saved[@"appliedMasks"] boolValue] ||
                  !WCKCornerObjectsEqual(view.layer.cornerCurve, saved[@"appliedCurve"]))) {
        // The host changed the view after our pass. Its new style wins; do not
        // overwrite it or restore the old snapshot later.
        WCKCornerClearView(view); saved = nil;
    }
    if (!enabled || !WCKCornerViewPaints(view, family)) { WCKCornerClearView(view); return; }
    if (!saved && view.layer.cornerRadius > 0.01) return; // host-owned geometry
    NSString *radiusFamily = ([family isEqualToString:@"chatFileCorner"] ||
        [family isEqualToString:@"chatLocationCorner"]) ? @"chatImageCorner" : family;
    CGFloat radius = (CGFloat)WCKCornerNumber(snapshot, [radiusFamily stringByAppendingString:@"Radius"],
                                               [snapshot[@"globalCornerRadius"] doubleValue], 24);
    radius = MIN(radius, MIN(view.bounds.size.width, view.bounds.size.height) / 2.0);
    if (radius <= 0.5) { WCKCornerClearView(view); return; }
    if (!saved) saved = [@{ @"hostRadius": @(view.layer.cornerRadius), @"hostMasks": @(view.layer.masksToBounds),
                            @"hostCurve": view.layer.cornerCurve ?: @"", @"radius": @(radius),
                            @"appliedMasks": @YES, @"appliedCurve": kCACornerCurveContinuous } mutableCopy];
    else saved[@"radius"] = @(radius);
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
    objc_setAssociatedObject(view, &sCornerViewMarkerKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void WCKCornerViewDidMove(id view, SEL cmd) {
    sViewDidMoveToWindow(view, cmd);
    if (![view isKindOfClass:UIView.class] || !NSThread.isMainThread) return;
    WCKCornerApplyToView(view);
    __weak UIView *weakView = view;
    dispatch_async(dispatch_get_main_queue(), ^{ WCKCornerApplyToView(weakView); });
}
static void WCKCornerViewSetBackground(id view, SEL cmd, UIColor *colour) {
    sViewSetBackgroundColor(view, cmd, colour);
    if (colour) WCKCornerApplyToView(view);
}
static void WCKCornerViewLayout(id view, SEL cmd) {
    sViewLayoutSubviews(view, cmd);
    WCKCornerApplyToView((UIView *)view);
}
static void WCKVerifiedLayerRestore(UIView *view) {
    NSDictionary *saved = objc_getAssociatedObject(view, &sVerifiedLayerStateKey);
    if (![saved isKindOfClass:NSDictionary.class]) return;
    if (fabs(view.layer.cornerRadius - [saved[@"appliedRadius"] doubleValue]) < 0.01)
        view.layer.cornerRadius = [saved[@"hostRadius"] doubleValue];
    if (view.layer.maskedCorners == [saved[@"appliedMask"] unsignedIntegerValue])
        view.layer.maskedCorners = [saved[@"hostMask"] unsignedIntegerValue];
    if (view.layer.masksToBounds == [saved[@"appliedClips"] boolValue])
        view.layer.masksToBounds = [saved[@"hostClips"] boolValue];
    if (WCKCornerObjectsEqual(view.layer.cornerCurve, kCACornerCurveContinuous)) {
        id curve = saved[@"hostCurve"];
        view.layer.cornerCurve = curve == [NSNull null] ? nil : curve;
    }
    objc_setAssociatedObject(view, &sVerifiedLayerStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL WCKCornerApplyLayerFamily(UIView *view, NSString *family, NSDictionary *snapshot) {
    NSString *enabledKey = [family stringByAppendingString:@"Enabled"];
    NSString *radiusKey = [family stringByAppendingString:@"Radius"];
    NSUInteger mask = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
        kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    if ([family isEqualToString:@"topbarCorner"] && [snapshot[@"topbarCornerTopFlatEnabled"] boolValue])
        mask = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    if ([family isEqualToString:@"toolbarCorner"] && [snapshot[@"toolbarCornerBottomFlatEnabled"] boolValue])
        mask = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    NSDictionary *saved = objc_getAssociatedObject(view, &sVerifiedLayerStateKey);
    if (saved && (fabs(view.layer.cornerRadius - [saved[@"appliedRadius"] doubleValue]) >= 0.01 ||
                  view.layer.maskedCorners != [saved[@"appliedMask"] unsignedIntegerValue] ||
                  view.layer.masksToBounds != [saved[@"appliedClips"] boolValue] ||
                  !WCKCornerObjectsEqual(view.layer.cornerCurve, kCACornerCurveContinuous))) {
        // The host changed the layer after our pass. Its value wins.
        objc_setAssociatedObject(view, &sVerifiedLayerStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        saved = nil;
    }
    if (!snapshot || ![snapshot[enabledKey] boolValue]) {
        WCKVerifiedLayerRestore(view); return NO;
    }
    CGFloat radius = (CGFloat)WCKCornerNumber(snapshot, radiusKey,
        [snapshot[@"globalCornerRadius"] doubleValue], 24);
    CGFloat limit = MIN(view.bounds.size.width, view.bounds.size.height) / 2.0;
    if (radius <= 0.5 || limit <= 0.5) { WCKVerifiedLayerRestore(view); return NO; }
    radius = MIN(radius, limit);
    if (!saved) {
        saved = @{ @"hostRadius": @(view.layer.cornerRadius),
            @"hostMask": @(view.layer.maskedCorners),
            @"hostClips": @(view.layer.masksToBounds),
            @"hostCurve": view.layer.cornerCurve ?: [NSNull null],
            @"appliedRadius": @(radius), @"appliedMask": @(mask),
            @"appliedClips": @YES };
    } else {
        NSMutableDictionary *updated = [saved mutableCopy];
        updated[@"appliedRadius"] = @(radius); updated[@"appliedMask"] = @(mask);
        saved = updated;
    }
    view.layer.cornerRadius = radius;
    view.layer.maskedCorners = mask;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
    objc_setAssociatedObject(view, &sVerifiedLayerStateKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}
static void WCKAvatarApply(id view, SEL cmd, WCKCornerVoidIMP original) {
    original(view, cmd);
    UIView *avatarView = (UIView *)view;
    if (!NSThread.isMainThread) return;
    NSDictionary *snapshot = WCKSettings.shared.snapshot;
    if (!WCKEnabled(@"corners")) return;
    BOOL chatScene = NO;
    UIResponder *next = (UIResponder *)avatarView;
    for (NSUInteger depth = 0; next && depth < 48; ++depth, next = next.nextResponder) {
        NSString *name = NSStringFromClass(next.class);
        if ([name rangeOfString:@"MsgContent" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"Chat" options:NSCaseInsensitiveSearch].location != NSNotFound) { chatScene = YES; break; }
    }
    NSString *enabledKey = chatScene ? @"avatarCornerChatPageEnabled" : @"avatarCornerEnabled";
    NSString *radiusKey = chatScene ? @"avatarCornerChatPageRadius" : @"avatarCornerRadius";
    CGFloat radius = (CGFloat)WCKCornerNumber(snapshot, radiusKey, 12, 24);
    if (![snapshot[enabledKey] boolValue]) {
        if (fabs(avatarView.layer.cornerRadius - radius) < 0.01) avatarView.layer.cornerRadius = 0;
        return;
    }

    CGFloat limit = MIN(avatarView.bounds.size.width, avatarView.bounds.size.height) / 2.0;
    if (limit <= 0.5) return;
    avatarView.layer.cornerRadius = MIN(radius, limit);
    avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    avatarView.layer.masksToBounds = YES;
}
static void WCKAvatarLayout(id view, SEL cmd) {
    WCKAvatarApply(view, cmd, sAvatarLayoutSubviews);
}
static void WCKProfileAvatarLayout(id view, SEL cmd) {
    WCKAvatarApply(view, cmd, sProfileAvatarLayoutSubviews);
}
static void WCKFakeAvatarLayout(id view, SEL cmd) {
    WCKAvatarApply(view, cmd, sFakeAvatarLayoutSubviews);
}
static void WCKMsgNavBarLayout(id view, SEL cmd) {
    sMsgNavBarLayoutSubviews(view, cmd);
    if (!NSThread.isMainThread) return;
    NSDictionary *snapshot = WCKSettings.shared.snapshot;
    if (!WCKEnabled(@"corners") || ![snapshot[@"topbarCornerEnabled"] boolValue]) return;
    WCKCornerApplyLayerFamily((UIView *)view, @"topbarCorner", snapshot);
}
static void WCKNewMsgNavBarLayout(id view, SEL cmd) {
    sNewMsgNavBarLayoutSubviews(view, cmd);
    if (!NSThread.isMainThread) return;
    NSDictionary *snapshot = WCKSettings.shared.snapshot;
    if (!WCKEnabled(@"corners") || ![snapshot[@"topbarCornerEnabled"] boolValue]) return;
    WCKCornerApplyLayerFamily((UIView *)view, @"topbarCorner", snapshot);
}
static void WCKTabBarLayout(id view, SEL cmd) {
    sTabBarLayoutSubviews(view, cmd);
    if (!NSThread.isMainThread) return;
    NSDictionary *snapshot = WCKSettings.shared.snapshot;
    if (!WCKEnabled(@"corners") || ![snapshot[@"toolbarCornerEnabled"] boolValue]) return;
    WCKCornerApplyLayerFamily((UIView *)view, @"toolbarCorner", snapshot);
}
static void WCKCornerVisitViews(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) [windows addObject:window];
    }
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:windows];
    NSUInteger visited = 0;
    while (queue.count && visited < 4000) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        ++visited;
        WCKCornerApplyToView(view);
        for (UIView *child in view.subviews) [queue addObject:child];
    }
}

static UIColor *WCKCornerDefaultFill(UITableView *table) {
    BOOL dark = NO;
    @try { dark = table.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark; }
    @catch (__unused NSException *exception) { dark = NO; }
    if (dark) return [UIColor colorWithRed:44 / 255.0 green:44 / 255.0 blue:46 / 255.0 alpha:1];
    return UIColor.whiteColor;
}
static BOOL WCKCornerContext(UITableViewCell *cell, NSDictionary *snapshot,
                             UITableView **tableOut, NSIndexPath **pathOut, NSInteger *rowsOut) {
    if (!cell.window || cell.hidden || cell.alpha < 0.01) return NO;
    UITableView *table = WCKCornerTable(cell);
    if (!table || !WCKCornerPageEnabled(WCKCornerOwner(table), snapshot)) return NO;
    NSIndexPath *path = [table indexPathForCell:cell];
    if (!path || path.section < 0 || path.section >= [table numberOfSections]) return NO;
    NSInteger rows = [table numberOfRowsInSection:path.section];
    if (path.row < 0 || path.row >= rows) return NO;
    if (tableOut) *tableOut = table;
    if (pathOut) *pathOut = path;
    if (rowsOut) *rowsOut = rows;
    return YES;
}

static void WCKCornerRestoreStyle(UITableViewCell *cell, WCKCornerState *state) {
    if (!state) return;
    for (WCKCornerLayerState *saved in state.layers) {
        CALayer *layer = saved.layer;
        if (!layer) continue;
        // Restore only our still-owned values. A host/theme write made after
        // ours wins, and is captured anew after its next original layout.
        if (saved.ownsGeometry) {
            if (layer.cornerRadius == saved.lastRadius) layer.cornerRadius = saved.radius;
            if (layer.maskedCorners == saved.lastMask) layer.maskedCorners = saved.mask;
            if (WCKCornerObjectsEqual(layer.cornerCurve, saved.lastCurve)) layer.cornerCurve = saved.curve;
        }
        if (saved.ownsBorder && layer.borderWidth == saved.lastWidth &&
            WCKCornerColorsEqual(layer.borderColor, saved.lastColor.CGColor)) {
            layer.borderWidth = saved.width;
            layer.borderColor = saved.color.CGColor;
        }
    }
    [state.layers removeAllObjects];
    if (state.ownsFill && WCKCornerObjectsEqual(cell.backgroundColor, state.appliedFill))
        cell.backgroundColor = state.hostFill;
    if (state.ownsViewFill && cell.backgroundView &&
        WCKCornerObjectsEqual(cell.backgroundView.backgroundColor, state.appliedViewFill))
        cell.backgroundView.backgroundColor = state.hostViewFill;
    state.ownsFill = NO; state.hostFill = nil; state.appliedFill = nil;
    state.ownsViewFill = NO; state.hostViewFill = nil; state.appliedViewFill = nil;
}
static void WCKCornerStyleLayer(CALayer *layer, CGFloat radius, NSUInteger mask,
                                 CGFloat width, UIColor *border, WCKCornerState *state) {
    if (!layer) return;
    for (WCKCornerLayerState *record in state.layers) if (record.layer == layer) return;
    WCKCornerLayerState *saved = [WCKCornerLayerState new]; saved.layer = layer;
    saved.radius = layer.cornerRadius; saved.mask = layer.maskedCorners; saved.curve = layer.cornerCurve;
    saved.lastRadius = radius; saved.lastMask = mask; saved.lastCurve = kCACornerCurveContinuous;
    saved.ownsGeometry = YES;
    // The host's masksToBounds is deliberately neither readjusted nor erased.
    layer.cornerRadius = radius; layer.maskedCorners = mask; layer.cornerCurve = kCACornerCurveContinuous;
    if (width > 0 && border) {
        saved.width = layer.borderWidth;
        saved.color = layer.borderColor ? [UIColor colorWithCGColor:layer.borderColor] : nil;
        saved.lastWidth = width; saved.lastColor = border; saved.ownsBorder = YES;
        layer.borderWidth = width; layer.borderColor = border.CGColor;
    }
    [state.layers addObject:saved];
}
static CGRect WCKCornerFrame(UITableViewCell *cell, CGRect incoming, NSDictionary *snapshot,
                              BOOL enabled, WCKCornerState **stateOut) {
    WCKCornerState *state = WCKCornerGetState(cell, NO);
    UITableView *table = WCKCornerTable(cell);
    CGRect host = incoming;
    UIView *parent = cell.superview;
    // Identical repeated layouts use our remembered baseline. If the cell moves
    // to a new wrapper/table, translate that baseline between parent coordinate
    // systems; never feed the old already-inset frame into the new table.
    if (state.ownsFrame && state.superview == parent &&
        CGRectEqualToRect(incoming, state.appliedFrame)) {
        // A cell can move between tables that share the same coordinate
        // parent. Recover the prior host frame even when table identity changed.
        host = state.hostFrame;
    } else if (state.ownsFrame && state.superview && parent && state.superview != parent) {
        // appliedFrame is stored in the old parent's coordinate space. Convert
        // it before comparing with the new parent's incoming frame; otherwise a
        // translated wrapper makes the equality check fail and freezes the inset.
        @try {
            CGRect appliedInParent = [state.superview convertRect:state.appliedFrame toView:parent];
            CGRect hostInParent = [state.superview convertRect:state.hostFrame toView:parent];
            if (WCKCornerFiniteRect(appliedInParent) && WCKCornerFiniteRect(hostInParent) &&
                CGRectEqualToRect(incoming, appliedInParent)) host = hostInParent;
        } @catch (__unused NSException *exception) { host = incoming; }
    }
    if (!WCKCornerFiniteRect(host)) host = incoming;
    if (state) state.ownsFrame = NO;
    if (!enabled || !WCKCornerFiniteRect(host) || !WCKCornerContext(cell, snapshot, &table, NULL, NULL)) {
        if (stateOut) *stateOut = state;
        return host;
    }
    CGRect bounds = table.bounds;
    if (!WCKCornerFiniteRect(bounds) || !parent) { if (stateOut) *stateOut = state; return host; }
    // table.bounds and cell.frame may use different coordinate systems when the
    // host inserts a wrapper view. Convert before applying the horizontal inset.
    CGRect visible = [table convertRect:bounds toView:parent];
    if (!WCKCornerFiniteRect(visible)) { if (stateOut) *stateOut = state; return host; }
    CGFloat margin = (CGFloat)WCKCornerNumber(snapshot, @"globalCornerMargin", 8, 30);
    CGFloat spacing = (CGFloat)WCKCornerNumber(snapshot, @"globalCornerSpacing", 8, 50);
    CGFloat left = MAX(CGRectGetMinX(host), CGRectGetMinX(visible) + margin);
    CGFloat right = MIN(CGRectGetMaxX(host), CGRectGetMaxX(visible) - margin);
    CGRect desired = host;
    if (margin > 0 && right - left > 1) { desired.origin.x = left; desired.size.width = right - left; }
    // Vertical gap belongs to the cell frame too; otherwise neighbouring cards
    // share an edge and their rounded corners disappear.
    if (spacing > 0 && CGRectGetHeight(host) > spacing + 1) {
        desired.origin.y = CGRectGetMinY(host) + spacing / 2.0;
        desired.size.height = CGRectGetHeight(host) - spacing;
    }
    if (!state && !CGRectEqualToRect(desired, host)) state = WCKCornerGetState(cell, YES);
    if (state) {
        state.hostFrame = host; state.appliedFrame = desired; state.table = table; state.superview = parent;
        state.ownsFrame = !CGRectEqualToRect(desired, host);
    }
    if (stateOut) *stateOut = state;
    return desired;
}
static void WCKCornerSetFrame(UITableViewCell *cell, SEL cmd, CGRect frame, WCKCornerFrameIMP original) {
    if (!NSThread.isMainThread || sCornerInternalFrameCell == cell ||
        (sCornerFrameDepth && sCornerFrameCell == cell)) {
        original(cell, cmd, frame); return;
    }
    UITableViewCell *previous = sCornerFrameCell; sCornerFrameCell = cell;
    ++sCornerFrameDepth;
    @try {
        CGRect desired = frame;
        @try { desired = WCKCornerFrame(cell, frame, WCKSettings.shared.snapshot, WCKEnabled(@"corners"), NULL); }
        @catch (__unused NSException *exception) { /* Preparation cannot swallow the original call. */ }
        original(cell, cmd, desired);
    } @finally { --sCornerFrameDepth; sCornerFrameCell = previous; }
}
static void WCKCornerLayout(UITableViewCell *cell, SEL cmd, WCKCornerVoidIMP original) {
    if (!NSThread.isMainThread || (sCornerLayoutDepth && sCornerLayoutCell == cell)) {
        original(cell, cmd); return;
    }
    UITableViewCell *previous = sCornerLayoutCell; sCornerLayoutCell = cell;
    ++sCornerLayoutDepth;
    @try {
        @try {
            if (!sCornerCells) sCornerCells = [NSHashTable weakObjectsHashTable];
            [sCornerCells addObject:cell];
            WCKCornerRestoreStyle(cell, WCKCornerGetState(cell, NO));
            CGRect desired = WCKCornerFrame(cell, cell.frame, WCKSettings.shared.snapshot,
                                             WCKEnabled(@"corners"), NULL);
            if (!CGRectEqualToRect(cell.frame, desired)) {
                UITableViewCell *previousInternal = sCornerInternalFrameCell; sCornerInternalFrameCell = cell;
                @try { cell.frame = desired; }
                @finally { sCornerInternalFrameCell = previousInternal; }
            }
        } @catch (__unused NSException *exception) { /* Still run the host's layout. */ }
        original(cell, cmd); // Keep contentView layout entirely under the host.
        @try {
            if (!WCKEnabled(@"corners")) return;
            NSDictionary *snapshot = WCKSettings.shared.snapshot;
            UITableView *table = nil;
            if (!WCKCornerContext(cell, snapshot, &table, NULL, NULL) ||
                !WCKCornerFiniteRect(cell.bounds)) return;
            WCKCornerState *state = WCKCornerGetState(cell, YES);
            // Every row is its own card; row-index masks left middle rows square.
            CGFloat radius = (CGFloat)WCKCornerNumber(snapshot, @"globalCornerRadius", 12, 24);
            radius = MIN(radius, MIN(cell.bounds.size.width, cell.bounds.size.height) / 2.0);
            NSUInteger mask = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            if (radius <= 0) mask = 0;
            CGFloat width = (CGFloat)WCKCornerNumber(snapshot, @"globalCornerStroke", 0, 4);
            UIColor *border = WCKCornerFill(snapshot, @"globalCornerStrokeColor");
            WCKCornerStyleLayer(cell.layer, radius, mask, width, border, state);
            WCKCornerStyleLayer(cell.backgroundView.layer, radius, mask, 0, nil, state);
            WCKCornerStyleLayer(cell.selectedBackgroundView.layer, radius, mask, 0, nil, state);
            // An empty setting means the card colour this module supplies, not
            // "leave the host transparent" - a transparent layer shows no corners.
            UIColor *fill = WCKCornerFill(snapshot, @"globalCornerFill") ?: WCKCornerDefaultFill(table);
            state.hostFill = cell.backgroundColor; state.appliedFill = fill; state.ownsFill = YES;
            cell.backgroundColor = fill;
            UIView *back = cell.backgroundView;
            if (back) {
                state.hostViewFill = back.backgroundColor; state.appliedViewFill = fill;
                state.ownsViewFill = YES; back.backgroundColor = fill;
            }
        } @catch (__unused NSException *exception) {
            WCKSetModuleStatus(@"corners.debug.last", @"列表圆角准备异常；保留宿主布局");
        }
    } @finally { --sCornerLayoutDepth; sCornerLayoutCell = previous; }
}

static void WCKCornerReuse(UITableViewCell *cell, SEL cmd, WCKCornerVoidIMP original) {
    if (!NSThread.isMainThread || (sCornerReuseDepth && sCornerReuseCell == cell)) {
        original(cell, cmd); return;
    }
    UITableViewCell *previous = sCornerReuseCell; sCornerReuseCell = cell;
    ++sCornerReuseDepth;
    @try {
        @try {
            WCKCornerState *state = WCKCornerGetState(cell, NO);
            WCKCornerRestoreStyle(cell, state);
            // Restore the frame only while the cell is offscreen; restoring a
            // visible cell makes the card snap to full width and back.
            if (cell.window == nil && state.ownsFrame) {
                CGRect restoreFrame = state.hostFrame;
                BOOL stillOwned = CGRectEqualToRect(cell.frame, state.appliedFrame);
                if (state.superview != cell.superview && state.superview && cell.superview) {
                    // If the host reparented a cell before reuse, only restore
                    // when its current frame is still our translated inset.
                    @try {
                        CGRect appliedInParent = [state.superview convertRect:state.appliedFrame toView:cell.superview];
                        CGRect hostInParent = [state.superview convertRect:state.hostFrame toView:cell.superview];
                        stillOwned = WCKCornerFiniteRect(appliedInParent) && WCKCornerFiniteRect(hostInParent) &&
                            CGRectEqualToRect(cell.frame, appliedInParent);
                        if (stillOwned) restoreFrame = hostInParent;
                    } @catch (__unused NSException *exception) { stillOwned = NO; }
                } else if (state.superview != cell.superview && cell.superview) {
                    // The old coordinate space is gone; do not overwrite a
                    // potentially host-authored frame in the new parent.
                    stillOwned = NO;
                }
                if (stillOwned) {
                    UITableViewCell *previousInternal = sCornerInternalFrameCell; sCornerInternalFrameCell = cell;
                    @try { cell.frame = restoreFrame; }
                    @finally { sCornerInternalFrameCell = previousInternal; }
                }
            }
            objc_setAssociatedObject(cell, &sCornerStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [sCornerCells removeObject:cell];
        } @catch (__unused NSException *exception) { /* Reuse remains a host operation. */ }
        original(cell, cmd);
    } @finally { --sCornerReuseDepth; sCornerReuseCell = previous; }
}
static void WCKMMCornerFrame(id c, SEL s, CGRect f) { WCKCornerSetFrame(c, s, f, sMMFrame); }
static void WCKMainCornerFrame(id c, SEL s, CGRect f) { WCKCornerSetFrame(c, s, f, sMainFrame); }
static void WCKMMCornerLayout(id c, SEL s) { WCKCornerLayout(c, s, sMMLayout); }
static void WCKMainCornerLayout(id c, SEL s) { WCKCornerLayout(c, s, sMainLayout); }
static void WCKMMCornerReuse(id c, SEL s) { WCKCornerReuse(c, s, sMMReuse); }
static void WCKMainCornerReuse(id c, SEL s) { WCKCornerReuse(c, s, sMainReuse); }


void WCKRefreshCorners(void) {
    if (!NSThread.isMainThread) return;
    // Coalesce slider/settings writes; never traverse and modify all UIViews.
    if (sCornerRefreshQueued) return;
    sCornerRefreshQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSArray<UITableViewCell *> *cells = sCornerCells.allObjects;
            NSUInteger end = MIN(cells.count, WCKCornerRefreshLimit);
            for (NSUInteger i = 0; i < end; ++i) {
                UITableViewCell *cell = cells[i];
                // No forced layout: the next natural pass applies the change
                // without snapping visible cards.
                [cell setNeedsLayout];
            }
            // Component-family application is disabled by default until its
            // real WeChat host anchor is verified. List cards remain active.
            if (WCKEnableUnverifiedComponentFamilies) WCKCornerVisitViews();
        } @catch (__unused NSException *exception) {
            WCKSetModuleStatus(@"corners.debug.last", @"列表刷新异常；保留宿主状态");
        } @finally { sCornerRefreshQueued = NO; }
    });
}
void WCKInstallCorners(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = NSClassFromString(@"MMTableViewCell");
        const char *frameArgs[] = {@encode(CGRect)};
        BOOL frame = WCKInstallHook(base, @selector(setFrame:), (IMP)WCKMMCornerFrame,
                                   (IMP *)&sMMFrame, "v", frameArgs, 1);
        BOOL layout = WCKInstallHook(base, @selector(layoutSubviews), (IMP)WCKMMCornerLayout,
                                    (IMP *)&sMMLayout, "v", NULL, 0);
        BOOL reuse = WCKInstallHook(base, @selector(prepareForReuse), (IMP)WCKMMCornerReuse,
                                   (IMP *)&sMMReuse, "v", NULL, 0);
        // NewMainFrameCell does not inherit MMTableViewCell in the target host;
        // install its own trampolines even for selectors inherited elsewhere.
        // MSHookMessageEx/class-local registration keeps this path isolated.
        Class main = NSClassFromString(@"NewMainFrameCell");
        BOOL mainReady = NO;
        if (main) {
            BOOL mf = WCKInstallHook(main, @selector(setFrame:), (IMP)WCKMainCornerFrame,
                                    (IMP *)&sMainFrame, "v", frameArgs, 1);
            BOOL ml = WCKInstallHook(main, @selector(layoutSubviews), (IMP)WCKMainCornerLayout,
                                    (IMP *)&sMainLayout, "v", NULL, 0);
            BOOL mr = WCKInstallHook(main, @selector(prepareForReuse), (IMP)WCKMainCornerReuse,
                                    (IMP *)&sMainReuse, "v", NULL, 0);
            mainReady = mf && ml && mr;
        }
        BOOL viewMoved = WCKInstallHook(UIView.class, @selector(didMoveToWindow),
            (IMP)WCKCornerViewDidMove, (IMP *)&sViewDidMoveToWindow, "v", NULL, 0);
        BOOL viewColour = WCKInstallHook(UIView.class, @selector(setBackgroundColor:),
            (IMP)WCKCornerViewSetBackground, (IMP *)&sViewSetBackgroundColor, "v",
            (const char *[]){"@"}, 1);
        BOOL viewLayout = WCKInstallHook(UIView.class, @selector(layoutSubviews),
            (IMP)WCKCornerViewLayout, (IMP *)&sViewLayoutSubviews, "v", NULL, 0);
        Class avatar = NSClassFromString(@"MMHeadImageView");
        Class profileAvatar = NSClassFromString(@"TLProfileImageView");
        Class fakeAvatar = NSClassFromString(@"FakeHeadImageView");
        BOOL avatarReady = WCKInstallHook(avatar, @selector(layoutSubviews),
            (IMP)WCKAvatarLayout, (IMP *)&sAvatarLayoutSubviews, "v", NULL, 0);
        BOOL profileAvatarReady = WCKInstallHook(profileAvatar, @selector(layoutSubviews),
            (IMP)WCKProfileAvatarLayout, (IMP *)&sProfileAvatarLayoutSubviews, "v", NULL, 0);
        BOOL fakeAvatarReady = WCKInstallHook(fakeAvatar, @selector(layoutSubviews),
            (IMP)WCKFakeAvatarLayout, (IMP *)&sFakeAvatarLayoutSubviews, "v", NULL, 0);
        Class navBar = NSClassFromString(@"MMMsgContentNavBar");
        Class newNavBar = NSClassFromString(@"MMNewMsgContentNavBar");
        BOOL navReady = WCKInstallHook(navBar, @selector(layoutSubviews),
            (IMP)WCKMsgNavBarLayout, (IMP *)&sMsgNavBarLayoutSubviews, "v", NULL, 0);
        BOOL newNavReady = WCKInstallHook(newNavBar, @selector(layoutSubviews),
            (IMP)WCKNewMsgNavBarLayout, (IMP *)&sNewMsgNavBarLayoutSubviews, "v", NULL, 0);
        Class tabBar = NSClassFromString(@"MMTabBar");
        BOOL tabReady = WCKInstallHook(tabBar, @selector(layoutSubviews),
            (IMP)WCKTabBarLayout, (IMP *)&sTabBarLayoutSubviews, "v", NULL, 0);
        WCKSetModuleStatus(@"corners.verified", (avatarReady || profileAvatarReady || fakeAvatarReady ||
            navReady || newNavReady || tabReady) ? @"ready" : @"未找到已核宿主类");
        WCKSetModuleStatus(@"corners.views", viewMoved && viewColour && viewLayout ? @"ready" : @"控件圆角 hook 不可用");
        WCKSetModuleStatus(@"corners", frame && layout && reuse && mainReady
            ? @"ready" : @"列表或首页单元格布局/恢复接口不可用");
        [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
            object:WCKSettings.shared queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { WCKRefreshCorners(); }];
    });
}
