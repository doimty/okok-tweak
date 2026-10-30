#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKSVGPalette.h"
#import <math.h>

// WCR evidence: list-cell candidates plus dedicated avatar/nav-bar/tab-bar
// paths. Component families can be opted in and are traversed with a view cap.
static char sCornerStateKey;
static NSHashTable<UITableViewCell *> *sCornerCells; // weak, main-thread only
static _Thread_local NSUInteger sCornerFrameDepth, sCornerLayoutDepth, sCornerReuseDepth;
static _Thread_local __unsafe_unretained UITableViewCell *sCornerFrameCell;
static _Thread_local __unsafe_unretained UITableViewCell *sCornerLayoutCell;
static _Thread_local __unsafe_unretained UITableViewCell *sCornerReuseCell;
static BOOL sCornerRefreshQueued;

@interface WCKCornerLayerState : NSObject
@property(nonatomic, weak) CALayer *layer;
@property(nonatomic) CGFloat radius, lastRadius, width, lastWidth;
@property(nonatomic) NSUInteger mask, lastMask;
@property(nonatomic, copy) NSString *curve, *lastCurve;
@property(nonatomic) BOOL ownsGeometry, ownsBorder, ownsClips;
@property(nonatomic) BOOL hostClips, lastClips;
@property(nonatomic, strong) UIColor *color, *lastColor;
@end
@implementation WCKCornerLayerState @end

@interface WCKCornerState : NSObject
@property(nonatomic) BOOL ownsFill, ownsViewFill, ownsSelected, ownsContentFill;
@property(nonatomic) BOOL ownsMask;
@property(nonatomic) BOOL ownsHostRadius;
@property(nonatomic) CGFloat hostCellRadius, hostBgRadius, hostContentRadius;
@property(nonatomic, weak) UIView *hostBgView;
@property(nonatomic, strong) CAShapeLayer *maskLayer;
@property(nonatomic, weak) CALayer *hostMask;
@property(nonatomic, strong) UIColor *hostContentFill, *appliedContentFill;
@property(nonatomic, strong) UIColor *hostFill, *appliedFill;
@property(nonatomic, strong) UIColor *hostViewFill, *appliedViewFill;
@property(nonatomic, weak) UIView *hostBackgroundView;
@property(nonatomic) CGRect hostSelectedFrame;
@property(nonatomic) CGFloat fixedSelectedRadius;
@property(nonatomic) CACornerMask fixedSelectedMask;
@property(nonatomic, weak) UIView *fixedSelectedView;
@property(nonatomic) CGRect appliedBounds;
@property(nonatomic) CGFloat appliedRadius;
@property(nonatomic) NSUInteger appliedCorners;
@property(nonatomic, strong) NSMutableArray<WCKCornerLayerState *> *layers;
@end
@implementation WCKCornerState @end

typedef void (*WCKCornerFrameIMP)(id, SEL, CGRect);
typedef void (*WCKCornerVoidIMP)(id, SEL);
static WCKCornerFrameIMP sMMFrame, sMainFrame, sBaseFrame;
static WCKCornerVoidIMP sMMLayout, sMainLayout, sMMReuse, sMainReuse, sBaseLayout, sBaseReuse;
static WCKCornerVoidIMP sContentLayout;
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
    if (!owner) return nil;
    // Match by name fragments: the class that owns the home table on a given
    // WeChat build is not guaranteed to be the exact name in any header dump.
    NSString *name = NSStringFromClass(owner.class);
    if (!name.length) return nil;
    if ([name containsString:@"MainFrame"] && [name containsString:@"ViewController"])
        return @"mainFrameCornerEnabled";
    if ([name containsString:@"Contacts"] && [name containsString:@"ViewController"])
        return @"homepageCornerEnabled";
    if ([name containsString:@"FindFriend"] || [name containsString:@"Discover"])
        return @"discoverPageCornerEnabled";
    if ([name containsString:@"MoreViewController"])
        return @"myPageCornerEnabled";
    if ([name containsString:@"ContactInfo"] || [name containsString:@"ContactProfile"] ||
        [name containsString:@"ChatInfo"] || [name containsString:@"ChatRoomInfo"] ||
        [name containsString:@"SessionInfo"] || [name containsString:@"ChatDetail"])
        return @"friendProfileCornerEnabled";
    return nil;
}
// Hot-path settings cache: the snapshot only changes with a settings write.
typedef struct {
    CGFloat radius, margin, spacing;
    BOOL valid;
} WCKCornerConfig;
static WCKCornerConfig sCornerConfig;
static void WCKCornerReloadConfig(void) {
    NSDictionary *snapshot = WCKSettings.shared.snapshot;
    sCornerConfig.radius = (CGFloat)WCKCornerNumber(snapshot, @"globalCornerRadius", 12, 24);
    sCornerConfig.margin = (CGFloat)WCKCornerNumber(snapshot, @"globalCornerMargin", 8, 30);
    sCornerConfig.spacing = (CGFloat)WCKCornerNumber(snapshot, @"globalCornerSpacing", 8, 50);
    sCornerConfig.valid = YES;
}
// Some builds place the list inside a container controller, so the responder
// chain never reaches the page controller. The table's own class is a stable
// second signal (e.g. MainFrameTableView is the home chat list).
static NSString *WCKCornerTablePageKey(UITableView *table) {
    if (!table) return nil;
    NSString *name = NSStringFromClass(table.class);
    if (!name.length) return nil;
    if ([name containsString:@"MainFrame"]) return @"mainFrameCornerEnabled";
    if ([name containsString:@"Contacts"]) return @"homepageCornerEnabled";
    if ([name containsString:@"FindFriend"] || [name containsString:@"Discover"])
        return @"discoverPageCornerEnabled";
    if ([name containsString:@"More"]) return @"myPageCornerEnabled";
    if ([name containsString:@"ContactInfo"] || [name containsString:@"Profile"] ||
        [name containsString:@"ChatInfo"] || [name containsString:@"ChatRoomInfo"] ||
        [name containsString:@"SessionInfo"] || [name containsString:@"ChatDetail"])
        return @"friendProfileCornerEnabled";
    return nil;
}
static NSString *WCKCornerPageKeyForTable(UIViewController *owner, UITableView *table) {
    NSString *key = WCKCornerPageKey(owner);
    return key ?: WCKCornerTablePageKey(table);
}
// ---- generic view corners: menus, search fields and other painted containers

// No host ABI or class-name binding is enforced; exact family switches still
// control which discovered views receive styling.
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
static void WCKCornerRoundChildren(UIView *view, CGFloat radius, NSString *family) {
    if (![family isEqualToString:@"searchCorner"] && ![family isEqualToString:@"menuCorner"] &&
        ![family isEqualToString:@"systemPopupCorner"]) return;
    Class fieldClass = NSClassFromString(@"UITextField");
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UITableViewCell.class]) continue;
        if (child.layer.cornerRadius > 0.01) continue; // host-owned
        if (fieldClass && [child isKindOfClass:fieldClass]) {
            child.layer.cornerRadius = radius;
            child.layer.cornerCurve = kCACornerCurveContinuous;
            child.layer.masksToBounds = YES;
            continue;
        }
        UIColor *colour = child.backgroundColor;
        if (colour && CGColorGetAlpha(colour.CGColor) > 0.01) {
            child.layer.cornerRadius = radius;
            child.layer.cornerCurve = kCACornerCurveContinuous;
            child.layer.masksToBounds = YES;
            continue;
        }
        for (UIView *inner in child.subviews) {
            if (inner.layer.cornerRadius > 0.01) continue;
            UIColor *innerColour = inner.backgroundColor;
            if (innerColour && CGColorGetAlpha(innerColour.CGColor) > 0.01) {
                inner.layer.cornerRadius = radius;
                inner.layer.cornerCurve = kCACornerCurveContinuous;
                inner.layer.masksToBounds = YES;
            }
        }
    }
}
static void WCKCornerApplyToView(UIView *view) {
    if (!NSThread.isMainThread || ![view isKindOfClass:UIView.class]) return;
    NSDictionary *snapshot = WCKSettings.shared.snapshot;
    if (!WCKEnabled(@"corners") || WCKCornerViewExcluded(view) ||
        [view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class] ||
        view.window == nil || view.hidden || view.alpha < 0.01) { WCKCornerClearView(view); return; }
    NSString *family = WCKCornerFamilyForView(view);
    BOOL enabled = [snapshot[[family stringByAppendingString:@"Enabled"]] boolValue];
    NSMutableDictionary *saved = [objc_getAssociatedObject(view, &sCornerViewMarkerKey) mutableCopy];
    if (saved && (view.layer.cornerRadius != [saved[@"radius"] doubleValue] ||
                  view.layer.masksToBounds != [saved[@"appliedMasks"] boolValue] ||
                  !WCKCornerObjectsEqual(view.layer.cornerCurve, saved[@"appliedCurve"]))) {
        // The host changed the view after our pass. Its new style wins; do not
        // overwrite it or restore the old snapshot later.
        WCKCornerClearView(view); saved = nil;
    }
    if (!enabled || !WCKCornerViewPaints(view, family)) {
        WCKCornerClearView(view);
        // The painted part of a search bar / menu lives in a subview, so keep
        // rounding children even when this view owns no visible background.
        if (enabled) {
            CGFloat childRadius = (CGFloat)WCKCornerNumber(snapshot,
                [family stringByAppendingString:@"Radius"], [snapshot[@"globalCornerRadius"] doubleValue], 24);
            WCKCornerRoundChildren(view, childRadius, family);
        }
        return;
    }
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
    WCKCornerRoundChildren(view, radius, family);
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
    // Neutral card tone; the old translucent white washed out to a light slab
    // on dark pages once it stacked over a light cell background.
    BOOL dark = NO;
    @try { dark = table.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark; }
    @catch (__unused NSException *exception) { dark = NO; }
    if (dark) return [UIColor colorWithRed:28 / 255.0 green:28 / 255.0 blue:30 / 255.0 alpha:1];
    return [UIColor colorWithRed:252 / 255.0 green:252 / 255.0 blue:252 / 255.0 alpha:1];
}
// One instance so the restore check can recognise exactly what we assigned.
static UIColor *WCKCornerTransparent(void) {
    static UIColor *colour;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ colour = UIColor.clearColor; });
    return colour;
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
        if (saved.ownsClips && layer.masksToBounds == saved.lastClips)
            layer.masksToBounds = saved.hostClips;
        if (saved.ownsBorder && layer.borderWidth == saved.lastWidth &&
            WCKCornerColorsEqual(layer.borderColor, saved.lastColor.CGColor)) {
            layer.borderWidth = saved.width;
            layer.borderColor = saved.color.CGColor;
        }
    }
    [state.layers removeAllObjects];
    if (state.ownsFill && WCKCornerObjectsEqual(cell.backgroundColor, state.appliedFill))
        cell.backgroundColor = state.hostFill;
    if (state.ownsSelected && state.fixedSelectedView && cell.selectedBackgroundView == state.fixedSelectedView)
        state.fixedSelectedView.frame = state.hostSelectedFrame;
    if (state.ownsMask && cell.layer.mask == state.maskLayer) cell.layer.mask = state.hostMask;
    state.ownsMask = NO; state.maskLayer = nil; state.hostMask = nil;
    if (state.ownsHostRadius) {
        cell.layer.cornerRadius = state.hostCellRadius;
        if (cell.backgroundView == state.hostBgView)
            cell.backgroundView.layer.cornerRadius = state.hostBgRadius;
        cell.contentView.layer.cornerRadius = state.hostContentRadius;
        state.ownsHostRadius = NO; state.hostBgView = nil;
    }
    if (state.ownsContentFill && WCKCornerObjectsEqual(cell.contentView.backgroundColor, state.appliedContentFill))
        cell.contentView.backgroundColor = state.hostContentFill;
    state.ownsFill = NO; state.hostFill = nil; state.appliedFill = nil;
    state.ownsViewFill = NO; state.hostViewFill = nil; state.appliedViewFill = nil;
    state.ownsSelected = NO; state.hostSelectedFrame = CGRectZero;
    state.ownsContentFill = NO; state.hostContentFill = nil; state.appliedContentFill = nil;
}
// 德发-style geometry: the row is inset when the host hands the frame to
// UIKit, so hit testing, content layout and animation all use the card size.
// Deliberately avoids indexPath/numberOfRowsInSection here: asking the table for
// row data from inside setFrame re-enters its row-data refresh.
static CGRect WCKCornerTargetFrame(UITableViewCell *cell, CGRect incoming,
                                   NSDictionary *snapshot) {
    UITableView *table = WCKCornerTable(cell);
    if (!table) return incoming;
    UIViewController *owner = WCKCornerOwner(table);
    NSString *pageKey = WCKCornerPageKeyForTable(owner, table);
    if (!pageKey || ![snapshot[pageKey] boolValue]) return incoming;
    if (!sCornerConfig.valid) WCKCornerReloadConfig();
    CGFloat margin = sCornerConfig.margin;
    margin = MIN(margin, MAX(0.0, incoming.size.width / 2.0 - 1.0));
    CGRect out = incoming;
    if (margin > 0 && out.size.width > 2.0 * margin) {
        out.origin.x += margin;
        out.size.width -= 2.0 * margin;
    }
    return out;
}
static void WCKCornerSetFrame(UITableViewCell *cell, SEL cmd, CGRect frame, WCKCornerFrameIMP original) {
    if (!NSThread.isMainThread || sCornerFrameDepth || (sCornerLayoutDepth && sCornerLayoutCell == cell)) {
        original(cell, cmd, frame); return;
    }
    UITableViewCell *previous = sCornerFrameCell; sCornerFrameCell = cell;
    ++sCornerFrameDepth;
    @try {
        CGRect target = frame;
        @try {
            if (WCKEnabled(@"corners"))
                target = WCKCornerTargetFrame(cell, frame, WCKSettings.shared.snapshot);
        } @catch (__unused NSException *exception) { target = frame; }
        // Depth stays raised so a subclass trampoline forwards instead of
        // insetting the same row twice.
        original(cell, cmd, target);
    } @finally { --sCornerFrameDepth; sCornerFrameCell = previous; }
}
// Visible diagnostic: the settings page prints this in the module status row,
// so a device screenshot tells us why rows were skipped instead of guessing.
// Aggregated per table class: the settings table must not hide the home list.
static NSMutableDictionary<NSString *, NSMutableDictionary *> *sCornerDiagTables;
static void WCKCornerNote(NSString *cellClass, UITableView *table, NSString *why, BOOL force) {
    static NSTimeInterval lastAt;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (!force && now - lastAt < 1.0) return;
    lastAt = now;
    if (!sCornerDiagTables) sCornerDiagTables = [NSMutableDictionary dictionary];
    NSString *tableName = table ? NSStringFromClass(table.class) : @"nil";
    NSString *ownerName = table ? NSStringFromClass(WCKCornerOwner(table).class) : @"nil";
    NSInteger count = [sCornerDiagTables[tableName][@"n"] integerValue] + 1;
    sCornerDiagTables[tableName] = [@{@"n": @(count), @"o": ownerName ?: @"nil",
        @"w": why ?: @"?", @"c": cellClass ?: @"?"} mutableCopy];
    if (sCornerDiagTables.count > 8) {
        NSString *oldest = sCornerDiagTables.allKeys.firstObject;
        if (oldest) [sCornerDiagTables removeObjectForKey:oldest];
    }
    NSArray<NSString *> *keys = [sCornerDiagTables.allKeys sortedArrayUsingComparator:^NSComparisonResult(
        NSString *a, NSString *b) {
        return [sCornerDiagTables[b][@"n"] compare:sCornerDiagTables[a][@"n"]];
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in keys) {
        if (parts.count == 3) break;
        NSDictionary *info = sCornerDiagTables[key];
        [parts addObject:[NSString stringWithFormat:@"%@×%@ o=%@ %@",
            key, info[@"n"], info[@"o"], info[@"w"]]];
    }
    WCKSetModuleStatus(@"corners.debug", [parts componentsJoinedByString:@" ; "]);
}
static void WCKCornerApplyStyle(UITableViewCell *cell) {
    @try {
            WCKCornerState *state = WCKCornerGetState(cell, NO);
            if (!WCKEnabled(@"corners")) { WCKCornerRestoreStyle(cell, state); return; }
            NSDictionary *snapshot = WCKSettings.shared.snapshot;
            // Home list cells lay out before the table registers them, so a nil
            // index path must not block the card: fall back to a middle row and
            // refine the group corners on the next pass that has one.
            UITableView *table = WCKCornerTable(cell);
            NSIndexPath *path = table ? [table indexPathForCell:cell] : nil;
            NSString *pageKey = WCKCornerPageKeyForTable(WCKCornerOwner(table), table);
            BOOL gateOn = pageKey && [snapshot[pageKey] boolValue];
            if (!table || !gateOn || !WCKCornerFiniteRect(cell.bounds)) {
                NSString *why = !table ? @"skip:no-table" :
                    (!gateOn ? [NSString stringWithFormat:@"gate=%@(0)", pageKey ?: @"none"]
                             : @"skip:zero-bounds");
                WCKCornerNote(NSStringFromClass(cell.class), table, why, YES);
                // Transient during scrolling/reuse: keep the style we already
                // applied instead of stripping it and losing the card.
                return;
            }
            if (!sCornerCells) sCornerCells = [NSHashTable weakObjectsHashTable];
            [sCornerCells addObject:cell];
            state = WCKCornerGetState(cell, YES);
            NSInteger rows = path ? [table numberOfRowsInSection:path.section] : 0;
            BOOL first = path ? path.row == 0 : NO;
            BOOL last = path && rows > 0 && path.row == rows - 1;
            CGRect bounds = cell.bounds;
            if (!sCornerConfig.valid) WCKCornerReloadConfig();
            CGFloat radius = sCornerConfig.radius;
            radius = MIN(radius, MIN(bounds.size.width, bounds.size.height) / 2.0);
            UIRectCorner corners = 0;
            if (first) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
            if (last) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
            if (radius <= 0.5) corners = 0;
            // Fast path: identical geometry already applied on this cell. Rows
            // lay out many times per scroll; rebuilding the path each pass was
            // the visible jank.
            BOOL fillIntact = state.ownsFill &&
                WCKCornerObjectsEqual(cell.backgroundColor, state.appliedFill);
            BOOL contentIntact = state.ownsContentFill &&
                WCKCornerObjectsEqual(cell.contentView.backgroundColor, state.appliedContentFill);
            if (state.maskLayer && cell.layer.mask == state.maskLayer &&
                CGRectEqualToRect(state.appliedBounds, bounds) &&
                state.appliedRadius == radius && state.appliedCorners == corners &&
                fillIntact && contentIntact)
                return;
            // A shape-layer mask survives host writes to backgroundColor and
            // layer geometry, which is what kept dropping the corners on scroll.
            if (!state.maskLayer) {
                state.maskLayer = [CAShapeLayer layer];
                state.hostMask = cell.layer.mask;
                state.ownsMask = YES;
            }
            CAShapeLayer *maskLayer = state.maskLayer;
            maskLayer.frame = bounds;
            // A nil path would mask the whole row away; middle rows keep a plain
            // rectangular path so the card stays continuous.
            CGFloat pathRadius = (corners == 0) ? 0 : radius;
            CGRect pathRect = (corners == 0) ? CGRectInset(bounds, -0.5, 0) : bounds;
            UIBezierPath *cornerPath = [UIBezierPath bezierPathWithRoundedRect:pathRect
                byRoundingCorners:corners cornerRadii:CGSizeMake(pathRadius, pathRadius)];
            maskLayer.path = cornerPath.CGPath;
            if (cell.layer.mask != maskLayer) cell.layer.mask = maskLayer;
            // WeChat rounds grouped cells itself; two radii on one corner read
            // as a notch. Clear the host value while our mask owns the shape.
            if (!state.ownsHostRadius) {
                state.hostCellRadius = cell.layer.cornerRadius;
                state.hostBgRadius = cell.backgroundView.layer.cornerRadius;
                state.hostContentRadius = cell.contentView.layer.cornerRadius;
                state.hostBgView = cell.backgroundView;
                state.ownsHostRadius = YES;
            }
            cell.layer.cornerRadius = 0;
            cell.backgroundView.layer.cornerRadius = 0;
            cell.contentView.layer.cornerRadius = 0;
            state.appliedBounds = bounds; state.appliedRadius = radius;
            state.appliedCorners = corners;
            UIColor *fill = WCKCornerFill(snapshot, @"globalCornerFill") ?: WCKCornerDefaultFill(table);
            if (!state.ownsFill) {
                state.hostFill = cell.backgroundColor;
                state.ownsFill = YES;
            }
            state.appliedFill = fill;
            cell.backgroundColor = fill;
            if (!state.ownsContentFill) {
                state.hostContentFill = cell.contentView.backgroundColor;
                state.appliedContentFill = WCKCornerTransparent();
                state.ownsContentFill = YES;
            }
            cell.contentView.backgroundColor = WCKCornerTransparent();
            UIView *selected = cell.selectedBackgroundView;
            if (selected) {
                if (!state.ownsSelected) {
                    state.fixedSelectedView = selected;
                    state.hostSelectedFrame = selected.frame;
                    state.ownsSelected = YES;
                }
            }
            WCKCornerNote(NSStringFromClass(cell.class), table, @"styled", NO);
    } @catch (__unused NSException *exception) {
        WCKSetModuleStatus(@"corners.debug.last", @"列表圆角准备异常；保留宿主布局");
    }
}
static void WCKCornerLayout(UITableViewCell *cell, SEL cmd, WCKCornerVoidIMP original) {
    if (!NSThread.isMainThread || (sCornerLayoutDepth && sCornerLayoutCell == cell)) {
        original(cell, cmd); return;
    }
    UITableViewCell *previous = sCornerLayoutCell; sCornerLayoutCell = cell;
    ++sCornerLayoutDepth;
    @try {
        original(cell, cmd);
        WCKCornerApplyStyle(cell);
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
            objc_setAssociatedObject(cell, &sCornerStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [sCornerCells removeObject:cell];
        } @catch (__unused NSException *exception) { /* Reuse remains a host operation. */ }
        original(cell, cmd);
    } @finally { --sCornerReuseDepth; sCornerReuseCell = previous; }
}
static void WCKMMCornerLayout(id c, SEL s) { WCKCornerLayout(c, s, sMMLayout); }
static void WCKMainCornerLayout(id c, SEL s) { WCKCornerLayout(c, s, sMainLayout); }
static void WCKMMCornerReuse(id c, SEL s) { WCKCornerReuse(c, s, sMMReuse); }
static void WCKMainCornerReuse(id c, SEL s) { WCKCornerReuse(c, s, sMainReuse); }
static void WCKMMCornerFrame(id c, SEL s, CGRect f) { WCKCornerSetFrame(c, s, f, sMMFrame); }
static void WCKMainCornerFrame(id c, SEL s, CGRect f) { WCKCornerSetFrame(c, s, f, sMainFrame); }
// Base class trampolines: subclasses that override the cell methods without
// calling super would otherwise never reach this path.
static void WCKBaseCornerLayout(id c, SEL s) { WCKCornerLayout(c, s, sBaseLayout); }
static void WCKBaseCornerReuse(id c, SEL s) { WCKCornerReuse(c, s, sBaseReuse); }
static void WCKBaseCornerFrame(id c, SEL s, CGRect f) { WCKCornerSetFrame(c, s, f, sBaseFrame); }
static void WCKCornerContentLayout(UIView *view, SEL cmd) {
    sContentLayout(view, cmd);
    if (!NSThread.isMainThread) return;
    UIView *host = view.superview;
    if (![host isKindOfClass:UITableViewCell.class]) return;
    // WeChat re-writes the cell background while its content lays out; styling
    // here keeps the card applied even when the cell's own layout is bypassed.
    WCKCornerApplyStyle((UITableViewCell *)host);
}

// Row-height spacing is deliberately NOT hooked: asking the table for its row
// count from inside heightForRow makes UIKit re-enter the same delegate and
// recurse (observed as a main-thread stack overflow on iOS 15 / WeChat 8.0.79).


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
            // Revisit current windows after settings changes; traversal is capped.
            WCKCornerVisitViews();
        } @catch (__unused NSException *exception) {
            WCKSetModuleStatus(@"corners.debug.last", @"列表刷新异常；保留宿主状态");
        } @finally { sCornerRefreshQueued = NO; }
    });
}
void WCKInstallCorners(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 德发-style: inset the row at setFrame: time, then clip it with corners.
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
        // Cover cells whose subclasses override the methods above without
        // calling super: the base class and the content view still run.
        BOOL baseReady = NO;
        if (UITableViewCell.class) {
            BOOL bf = WCKInstallHook(UITableViewCell.class, @selector(setFrame:),
                (IMP)WCKBaseCornerFrame, (IMP *)&sBaseFrame, "v", frameArgs, 1);
            BOOL bl = WCKInstallHook(UITableViewCell.class, @selector(layoutSubviews),
                (IMP)WCKBaseCornerLayout, (IMP *)&sBaseLayout, "v", NULL, 0);
            BOOL br = WCKInstallHook(UITableViewCell.class, @selector(prepareForReuse),
                (IMP)WCKBaseCornerReuse, (IMP *)&sBaseReuse, "v", NULL, 0);
            baseReady = bf && bl && br;
        }
        BOOL contentReady = NO;
        Class contentClass = NSClassFromString(@"UITableViewCellContentView");
        if (!contentClass) contentClass = NSClassFromString(@"UITableViewCellContent");
        if (contentClass)
            contentReady = WCKInstallHook(contentClass, @selector(layoutSubviews),
                (IMP)WCKCornerContentLayout, (IMP *)&sContentLayout, "v", NULL, 0);
        // Optional safety net; its absence must not disable the cell hooks.
        (void)contentReady;
        // No row-height hook here: it recursed through numberOfRowsInSection:
        // on iOS 15 and crashed the main thread. Spacing stays a visual-only gap
        // until a non-reentrant way to grow row height exists.
        BOOL viewMoved = WCKInstallHook(UIView.class, @selector(didMoveToWindow),
            (IMP)WCKCornerViewDidMove, (IMP *)&sViewDidMoveToWindow, "v", NULL, 0);
        BOOL viewColour = WCKInstallHook(UIView.class, @selector(setBackgroundColor:),
            (IMP)WCKCornerViewSetBackground, (IMP *)&sViewSetBackgroundColor, "v",
            (const char *[]){"@"}, 1);
        BOOL viewLayout = WCKInstallHook(UIView.class, @selector(layoutSubviews),
            (IMP)WCKCornerViewLayout, (IMP *)&sViewLayoutSubviews, "v", NULL, 0);
        // Host classes differ between WeChat builds. A missing class is not an
        // error: skip it so one absent host never disables the others.
        Class avatar = NSClassFromString(@"MMHeadImageView");
        Class profileAvatar = NSClassFromString(@"TLProfileImageView");
        Class fakeAvatar = NSClassFromString(@"FakeHeadImageView");
        BOOL avatarReady = avatar && WCKInstallHook(avatar, @selector(layoutSubviews),
            (IMP)WCKAvatarLayout, (IMP *)&sAvatarLayoutSubviews, "v", NULL, 0);
        BOOL profileAvatarReady = profileAvatar && WCKInstallHook(profileAvatar, @selector(layoutSubviews),
            (IMP)WCKProfileAvatarLayout, (IMP *)&sProfileAvatarLayoutSubviews, "v", NULL, 0);
        BOOL fakeAvatarReady = fakeAvatar && WCKInstallHook(fakeAvatar, @selector(layoutSubviews),
            (IMP)WCKFakeAvatarLayout, (IMP *)&sFakeAvatarLayoutSubviews, "v", NULL, 0);
        Class navBar = NSClassFromString(@"MMMsgContentNavBar");
        Class newNavBar = NSClassFromString(@"MMNewMsgContentNavBar");
        BOOL navReady = navBar && WCKInstallHook(navBar, @selector(layoutSubviews),
            (IMP)WCKMsgNavBarLayout, (IMP *)&sMsgNavBarLayoutSubviews, "v", NULL, 0);
        BOOL newNavReady = newNavBar && WCKInstallHook(newNavBar, @selector(layoutSubviews),
            (IMP)WCKNewMsgNavBarLayout, (IMP *)&sNewMsgNavBarLayoutSubviews, "v", NULL, 0);
        Class tabBar = NSClassFromString(@"MMTabBar");
        BOOL tabReady = tabBar && WCKInstallHook(tabBar, @selector(layoutSubviews),
            (IMP)WCKTabBarLayout, (IMP *)&sTabBarLayoutSubviews, "v", NULL, 0);
        WCKSetModuleStatus(@"corners.verified", (avatarReady || profileAvatarReady || fakeAvatarReady ||
            navReady || newNavReady || tabReady) ? @"ready" : @"未找到已核宿主类");
        WCKSetModuleStatus(@"corners.views", viewMoved && viewColour && viewLayout ? @"ready" : @"控件圆角 hook 不可用");
        WCKSetModuleStatus(@"corners", frame && layout && reuse && mainReady && baseReady
            ? @"ready" : @"列表或首页单元格布局/恢复接口不可用");
        [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
            object:WCKSettings.shared queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) {
                WCKCornerReloadConfig();
                WCKRefreshCorners();
            }];
        WCKCornerReloadConfig();
    });
}
void WCKInstallCornersLate(void) {
    // The home list may load its cell class after the dylib; retry once, with
    // statically stored originals (never a per-instance lookup that can miss).
    static BOOL done = NO;
    if (done) return;
    Class main = NSClassFromString(@"NewMainFrameCell");
    if (!main) return;
    done = YES;
    const char *frameArgs[] = {@encode(CGRect)};
    IMP original = NULL;
    if (!sMainFrame && WCKInstallHook(main, @selector(setFrame:), (IMP)WCKMainCornerFrame,
                                      &original, "v", frameArgs, 1) && original)
        sMainFrame = (WCKCornerFrameIMP)original;
    original = NULL;
    if (!sMainLayout && WCKInstallHook(main, @selector(layoutSubviews), (IMP)WCKMainCornerLayout,
                                       &original, "v", NULL, 0) && original)
        sMainLayout = (WCKCornerVoidIMP)original;
    original = NULL;
    if (!sMainReuse && WCKInstallHook(main, @selector(prepareForReuse), (IMP)WCKMainCornerReuse,
                                      &original, "v", NULL, 0) && original)
        sMainReuse = (WCKCornerVoidIMP)original;
}
