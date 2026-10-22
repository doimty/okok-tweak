#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"

// Global corner rounding. Two scopes:
//   list - table/collection cells only (low risk, visible in every list)
//   all  - any view that actually paints a background colour
// Excluded: image/text content, effect views, scroll containers/windows, and the
// keyboard window. masksToBounds is only enabled on views we recolour, so child
// content and shadows are not clipped by default.

static void (*sOriginalDidMoveToWindow)(id, SEL);
static void (*sOriginalSetBackgroundColor)(id, SEL, UIColor *);
static void (*sOriginalCellLayout)(id, SEL);

static NSArray<NSString *> *WCKCornerExcludedClassNames(void) {
    static NSArray *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"UIImageView", @"UILabel", @"UITextView", @"UITextField", @"UIVisualEffectView",
                  @"UIScrollView", @"UITableView", @"UICollectionView", @"UIWebView", @"WKWebView",
                  @"UINavigationBar", @"UITabBar", @"UIToolbar", @"UIWindow", @"UIInputSetContainerView",
                  @"UIInputView", @"UIPickerView", @"UIDatePicker", @"UIActivityIndicatorView",
                  @"UIProgressView", @"UISwitch", @"UISlider", @"UISegmentedControl"];
    });
    return names;
}

static BOOL WCKCornerClassExcluded(Class cls) {
    for (NSString *name in WCKCornerExcludedClassNames()) {
        Class excluded = NSClassFromString(name);
        if (excluded && [cls isSubclassOfClass:excluded]) return YES;
    }
    return NO;
}

static double WCKCornerRadius(void) {
    id value = WCKSettings.shared.snapshot[@"cornersRadius"];
    if (![value isKindOfClass:NSNumber.class]) return 12.0;
    double radius = [value doubleValue];
    if (!isfinite(radius)) return 12.0;
    return MIN(24.0, MAX(0.0, radius));
}

static double WCKCornerNumber(NSString *key, double fallback, double low, double high) {
    id value = WCKSettings.shared.snapshot[key];
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    double number = [value doubleValue];
    if (!isfinite(number)) return fallback;
    return MIN(high, MAX(low, number));
}

static double WCKCornerMargin(void) { return WCKCornerNumber(@"cornersMargin", 8, 0, 24); }
static double WCKCornerSpacing(void) { return WCKCornerNumber(@"cornersSpacing", 6, 0, 24); }
static double WCKCornerStrokeWidth(void) { return WCKCornerNumber(@"cornersStrokeWidth", 0, 0, 4); }

static UIColor *WCKCornerColour(NSString *key) {
    id text = WCKSettings.shared.snapshot[key];
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *hex = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![hex hasPrefix:@"#"] || hex.length != 7) return nil;
    unsigned value = 0;
    if (![[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&value]) return nil;
    return [UIColor colorWithRed:((value >> 16) & 255) / 255.0
                           green:((value >> 8) & 255) / 255.0
                            blue:(value & 255) / 255.0 alpha:1];
}

static BOOL WCKCornerScopeIsAll(void) {
    id scope = WCKSettings.shared.snapshot[@"cornersScope"];
    return [scope isKindOfClass:NSString.class] && [scope isEqualToString:@"all"];
}

static BOOL WCKPaintsBackground(UIView *view) {
    UIColor *colour = view.backgroundColor;
    if (!colour) return NO;
    CGFloat alpha = 1;
    if (![colour getWhite:NULL alpha:&alpha] && ![colour getRed:NULL green:NULL blue:NULL alpha:&alpha])
        return NO;
    return alpha > 0.01;
}

static BOOL WCKCornerEligible(UIView *view) {
    if (![view isKindOfClass:UIView.class]) return NO;
    if (view.window == nil || view.hidden || view.alpha < 0.01) return NO;
    if (WCKCornerClassExcluded([view class])) return NO;
    if (WCKCornerScopeIsAll()) return WCKPaintsBackground(view);
    // List scope: cells and their content view only.
    BOOL cell = [view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class];
    if (cell) return YES;
    UIView *parent = view.superview;
    return parent && ([parent isKindOfClass:UITableViewCell.class] ||
                      [parent isKindOfClass:UICollectionViewCell.class]);
}

static void WCKApplyCorner(UIView *view);

// Card layout: shrink the cell's content and background so the list reads as
// separated cards. Everything is recomputed from the cell bounds on every
// layout, so recycled cells and rotation stay consistent.
static void WCKApplyCardLayout(UITableViewCell *cell) {
    if (!NSThread.isMainThread || !WCKEnabled(@"corners") || WCKCornerScopeIsAll()) return;
    @try {
        CGRect bounds = cell.bounds;
        if (bounds.size.width < 2 || bounds.size.height < 2) return;
        CGFloat margin = (CGFloat)WCKCornerMargin(), spacing = (CGFloat)WCKCornerSpacing();
        if (margin <= 0 && spacing <= 0) return;
        CGRect card = CGRectInset(bounds, margin, spacing / 2.0);
        if (card.size.width <= 1 || card.size.height <= 1) return;
        UIView *background = cell.backgroundView;
        if (background && !CGRectEqualToRect(background.frame, card)) background.frame = card;
        UIView *content = cell.contentView;
        if (content && !CGRectEqualToRect(content.frame, card)) content.frame = card;
    } @catch (__unused NSException *exception) {
        WCKSetModuleStatus(@"corners.debug.last", @"卡片边距调整异常，已跳过");
    }
}

static void WCKCornerCellLayout(id cell, SEL cmd) {
    sOriginalCellLayout(cell, cmd);
    if (!NSThread.isMainThread) return;
    WCKApplyCardLayout(cell);
    WCKApplyCorner(cell);
    WCKApplyCorner(((UITableViewCell *)cell).contentView);
    WCKApplyCorner(((UITableViewCell *)cell).backgroundView);
}

static void WCKApplyCorner(UIView *view) {
    if (!NSThread.isMainThread || !WCKEnabled(@"corners")) return;
    @try {
        if (!WCKCornerEligible(view)) return;
        CGFloat radius = (CGFloat)WCKCornerRadius();
        CALayer *layer = view.layer;
        if (radius <= 0.5) {
            if (layer.cornerRadius != 0) { layer.cornerRadius = 0; layer.masksToBounds = NO; }
            return;
        }
        if (fabs(layer.cornerRadius - radius) > 0.01) {
            layer.cornerRadius = radius;
            layer.cornerCurve = kCACornerCurveContinuous;
        }
        // Only clip when this view itself paints; otherwise children may need
        // to draw outside (badges, shadows, popovers).
        UIColor *fill = WCKCornerColour(@"cornersFill");
        if (fill && ![view.backgroundColor isEqual:fill]) view.backgroundColor = fill;
        CGFloat stroke = (CGFloat)WCKCornerStrokeWidth();
        UIColor *strokeColour = WCKCornerColour(@"cornersStrokeColor");
        if (stroke > 0.05 && strokeColour) {
            layer.borderWidth = stroke;
            layer.borderColor = strokeColour.CGColor;
        } else if (layer.borderWidth != 0) {
            layer.borderWidth = 0;
        }
        layer.masksToBounds = WCKPaintsBackground(view);   // a border needs no clipping
    } @catch (__unused NSException *exception) {
        WCKSetModuleStatus(@"corners.debug.last", @"圆角设置异常，已跳过该视图");
    }
}

static void WCKCornerDidMoveToWindow(id view, SEL cmd) {
    sOriginalDidMoveToWindow(view, cmd);
    if (!NSThread.isMainThread) return;
    WCKApplyCorner(view);
}

static void WCKCornerSetBackgroundColor(id view, SEL cmd, UIColor *colour) {
    sOriginalSetBackgroundColor(view, cmd, colour);
    if (!NSThread.isMainThread || !colour) return;
    WCKApplyCorner(view);
}

void WCKRefreshCorners(void) {
    if (!NSThread.isMainThread) return;
    @try {
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
            WCKApplyCorner(view);
            for (UIView *child in view.subviews) [queue addObject:child];
        }
    } @catch (__unused NSException *exception) {
        WCKSetModuleStatus(@"corners.debug.last", @"遍历视图异常，已保留现状");
    }
}

void WCKInstallCorners(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL hook = WCKInstallHook(UIView.class, @selector(didMoveToWindow),
            (IMP)WCKCornerDidMoveToWindow, (IMP *)&sOriginalDidMoveToWindow, "v", NULL, 0);
        BOOL colour = WCKInstallHook(UIView.class, @selector(setBackgroundColor:),
            (IMP)WCKCornerSetBackgroundColor, (IMP *)&sOriginalSetBackgroundColor, "v",
            (const char *[]){ "@" }, 1);
        BOOL table = WCKInstallHook(UITableViewCell.class, @selector(layoutSubviews),
            (IMP)WCKCornerCellLayout, (IMP *)&sOriginalCellLayout, "v", NULL, 0);
        BOOL collection = table;
        if (!collection) {
            collection = WCKInstallHook(UICollectionViewCell.class, @selector(layoutSubviews),
                (IMP)WCKCornerCellLayout, (IMP *)&sOriginalCellLayout, "v", NULL, 0);
        }
        WCKSetModuleStatus(@"corners", hook && colour ? @"ready" : @"圆角 hook 不可用");
        if (!hook && !colour) return;
        [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                WCKRefreshCorners();
            }];
    });
}
