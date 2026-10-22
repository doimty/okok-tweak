#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKSVGSelection.h"
#import <string.h>

// Immutable recipes contain arguments, never an output image or a view.
typedef NS_ENUM(NSUInteger, WCKSVGKind) { WCKSVGTheme, WCKSVGVM, WCKSVGEngine };
typedef NS_ENUM(NSUInteger, WCKSVGOperation) { WCKSVGModeOp, WCKSVGInsetsOp, WCKSVGResizeOp, WCKSVGAlignOp };
typedef NS_ENUM(NSUInteger, WCKSVGSlotKind) { WCKSVGNormal, WCKSVGHighlighted, WCKSVGButton };
typedef id (*WCKThemeIMP)(id, SEL, id, CGSize, id, double, int, BOOL);
typedef id (*WCKEngineIMP)(id, SEL, id, CGSize, double, double, double, id);

@interface WCKSVGRequest : NSObject
@property(nonatomic, readonly) WCKSVGKind kind;
@property(nonatomic, weak, readonly) id receiver;
@property(nonatomic, readonly) SEL selector;
@property(nonatomic, readonly) IMP original;
@property(nonatomic, copy, readonly) id payload;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, strong, readonly) UIColor *color;
@property(nonatomic, readonly) CGSize size;
@property(nonatomic, readonly) double scale, rotation, opacity;
@property(nonatomic, readonly) int angle;
@property(nonatomic, readonly) BOOL ignore;
- (instancetype)initWithKind:(WCKSVGKind)kind receiver:(id)receiver selector:(SEL)selector
    original:(IMP)original payload:(id)payload name:(NSString *)name color:(UIColor *)color
    size:(CGSize)size scale:(double)scale rotation:(double)rotation opacity:(double)opacity
    angle:(int)angle ignore:(BOOL)ignore;
@end
@implementation WCKSVGRequest
- (instancetype)initWithKind:(WCKSVGKind)kind receiver:(id)receiver selector:(SEL)selector
    original:(IMP)original payload:(id)payload name:(NSString *)name color:(UIColor *)color
    size:(CGSize)size scale:(double)scale rotation:(double)rotation opacity:(double)opacity
    angle:(int)angle ignore:(BOOL)ignore {
    if ((self = [super init])) {
        _kind = kind; _receiver = receiver; _selector = selector; _original = original;
        _payload = [payload copy]; _name = [name copy]; _color = color; _size = size;
        _scale = scale; _rotation = rotation; _opacity = opacity; _angle = angle; _ignore = ignore;
    }
    return self;
}
@end

@interface WCKSVGStep : NSObject
@property(nonatomic, readonly) WCKSVGOperation operation;
@property(nonatomic, readonly) UIEdgeInsets insets;
@property(nonatomic, readonly) NSInteger mode;
- (instancetype)initWithOperation:(WCKSVGOperation)operation insets:(UIEdgeInsets)insets mode:(NSInteger)mode;
@end
@implementation WCKSVGStep
- (instancetype)initWithOperation:(WCKSVGOperation)operation insets:(UIEdgeInsets)insets mode:(NSInteger)mode {
    if ((self = [super init])) { _operation = operation; _insets = insets; _mode = mode; }
    return self;
}
@end

@interface WCKSVGStamp : NSObject
@property(nonatomic, strong, readonly) WCKSVGRequest *request;
@property(nonatomic, copy, readonly) NSArray<WCKSVGStep *> *steps;
@property(nonatomic, readonly) BOOL tinted, ambiguous;
@property(nonatomic, readonly) uint32_t rgb;
- (instancetype)initWithRequest:(WCKSVGRequest *)request steps:(NSArray<WCKSVGStep *> *)steps
    tinted:(BOOL)tinted rgb:(uint32_t)rgb;
@end
@implementation WCKSVGStamp
- (instancetype)initWithRequest:(WCKSVGRequest *)request steps:(NSArray<WCKSVGStep *> *)steps
    tinted:(BOOL)tinted rgb:(uint32_t)rgb {
    if ((self = [super init])) {
        _request = request; _steps = [steps copy]; _tinted = tinted; _rgb = tinted ? rgb : 0;
        _ambiguous = request == nil;
    }
    return self;
}
@end

@interface WCKSVGSlot : NSObject
@property(nonatomic, strong) WCKSVGStamp *stamp;
@property(nonatomic, weak) UIImage *last;
@end
@implementation WCKSVGSlot
@end
@interface WCKSVGDriver : NSObject
@property(nonatomic, strong) WCKSVGSlot *normal, *highlighted;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, WCKSVGSlot *> *states;
@end
@implementation WCKSVGDriver
@end

static char sDriverKey; // Associations are used on views only, never cached UIImages.
static NSMapTable<UIImage *, WCKSVGStamp *> *sProvenance;
static NSHashTable<UIImage *> *sConflictedImages; // weak quarantine; pointer identity
static NSLock *sProvenanceLock;
static NSHashTable<UIView *> *sSVGViews; // main-thread only, weak
static id sSettingsObserver;
static _Thread_local NSUInteger sFactoryDepth, sTransformDepth, sViewDepth;
// Lexical, non-owning assignment scope. A nested setter can supersede a pending
// replay even if it restores the same image pointer (A -> B -> A).
typedef struct {
    __unsafe_unretained id view;
    WCKSVGSlotKind kind;
    UIControlState state;
    BOOL superseded;
} WCKSVGAssignmentScope;
static _Thread_local WCKSVGAssignmentScope *sAssignmentScope;
// Borrowed only for the lexical lifetime of WCKSVGNameScope's strong local.
static _Thread_local void *sScopeName;
static const NSUInteger WCKSVGMaximumButtonStates = 32;
static WCKThemeIMP sOriginalTheme;
static WCKEngineIMP sOriginalVM, sOriginalEngine;
static id (*sOriginalConfig)(id, SEL, id, id);
static id (*sOriginalFile)(id, SEL, id, CGSize, id, double, double);
static id (*sOriginalAdapted)(id, SEL, id, id, id);
static id (*sOriginalMode)(id, SEL, UIImageRenderingMode);
static id (*sOriginalInsets)(id, SEL, UIEdgeInsets);
static id (*sOriginalResize)(id, SEL, UIEdgeInsets, UIImageResizingMode);
static id (*sOriginalAlign)(id, SEL, UIEdgeInsets);
static void (*sOriginalImage)(id, SEL, UIImage *);
static void (*sOriginalHighlighted)(id, SEL, UIImage *);
static void (*sOriginalButton)(id, SEL, UIImage *, UIControlState);
static void (*sOriginalImageTrait)(id, SEL, UITraitCollection *);
static void (*sOriginalButtonTrait)(id, SEL, UITraitCollection *);

static void WCKSVGDiagnostic(NSString *key, NSString *status) {
    @try { WCKSetModuleStatus([@"svgTint.debug." stringByAppendingString:key], status); }
    @catch (__unused NSException *exception) { /* Diagnostics cannot change host behavior. */ }
}
static void WCKSVGInitMap(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sProvenanceLock = [NSLock new];
        sProvenance = [NSMapTable mapTableWithKeyOptions:
            NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
            valueOptions:NSPointerFunctionsStrongMemory];
        sConflictedImages = [NSHashTable hashTableWithOptions:
            NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
    });
}
static WCKSVGStamp *WCKSVGLookup(id image) {
    @try {
        if (![image isKindOfClass:UIImage.class]) return nil;
        WCKSVGInitMap();
        [sProvenanceLock lock];
        @try { return [sConflictedImages containsObject:image] ? nil : [sProvenance objectForKey:image]; }
        @finally { [sProvenanceLock unlock]; }
    } @catch (__unused NSException *exception) {
        WCKSVGDiagnostic(@"provenance", @"来源读取异常；保留当前图"); return nil;
    }
}
static BOOL WCKSVGSameDouble(double a, double b) { return memcmp(&a, &b, sizeof(a)) == 0; }
// Comparisons (including UIColor equality) are deliberately outside the map lock.
static BOOL WCKSVGSameRequest(WCKSVGRequest *a, WCKSVGRequest *b) {
    if (a == b) return YES;
    id receiver = a.receiver;
    return a && b && receiver && receiver == b.receiver && a.kind == b.kind &&
        a.selector == b.selector && a.original == b.original && [a.payload isEqual:b.payload] &&
        [a.name isEqualToString:b.name] && (a.color == b.color || [a.color isEqual:b.color]) &&
        WCKSVGSameDouble(a.size.width, b.size.width) && WCKSVGSameDouble(a.size.height, b.size.height) &&
        WCKSVGSameDouble(a.scale, b.scale) && WCKSVGSameDouble(a.rotation, b.rotation) &&
        WCKSVGSameDouble(a.opacity, b.opacity) && a.angle == b.angle && a.ignore == b.ignore;
}
static BOOL WCKSVGSameStamp(WCKSVGStamp *a, WCKSVGStamp *b) {
    if (a == b) return a && !a.ambiguous;
    if (!a || !b || a.ambiguous || b.ambiguous || a.tinted != b.tinted || a.rgb != b.rgb ||
        !WCKSVGSameRequest(a.request, b.request) || a.steps.count != b.steps.count) return NO;
    for (NSUInteger i = 0; i < a.steps.count; ++i) {
        WCKSVGStep *x = a.steps[i], *y = b.steps[i];
        if (x.operation != y.operation || x.mode != y.mode ||
            !UIEdgeInsetsEqualToEdgeInsets(x.insets, y.insets)) return NO;
    }
    return YES;
}

// Publication is fail-closed. Quarantine genuine conflicts for the lifetime of
// the weak image key; deleting only the map entry would let a later request
// claim the same live cached image. Equality remains outside the map lock.
static WCKSVGStamp *WCKSVGStore(id image, WCKSVGStamp *stamp, WCKSVGStamp *selfInput) {
    @try {
        if (![image isKindOfClass:UIImage.class] || !stamp || stamp.ambiguous) return nil;
        WCKSVGInitMap();
        for (NSUInteger attempt = 0; attempt < 3; ++attempt) {
            WCKSVGStamp *old = WCKSVGLookup(image);
            BOOL same = old && WCKSVGSameStamp(old, stamp);
            BOOL conflict = old && (old.ambiguous || (old != selfInput && !same));
            WCKSVGStamp *next = !old || old == selfInput ? stamp : old;
            BOOL published = NO, quarantined = NO;
            [sProvenanceLock lock];
            @try {
                // The quarantine check and CAS must be one locked operation.
                if ([sConflictedImages containsObject:image]) quarantined = YES;
                else if ([sProvenance objectForKey:image] == old) {
                    if (conflict) {
                        [sConflictedImages addObject:image];
                        [sProvenance removeObjectForKey:image]; quarantined = YES;
                    } else { [sProvenance setObject:next forKey:image]; published = YES; }
                }
            } @finally { [sProvenanceLock unlock]; }
            if (quarantined) {
                WCKSVGDiagnostic(@"alias", @"同对象来源冲突；隔离来源并保留当前图"); return nil;
            }
            if (published) return next;
        }
        // Returning another writer's stamp would mislabel this result.
        WCKSVGDiagnostic(@"contention", @"来源发布争用超过3次；保留当前图"); return nil;
    } @catch (__unused NSException *exception) {
        WCKSVGDiagnostic(@"provenance", @"来源写入异常；保留当前图"); return nil;
    }
}

static id WCKSVGNameScope(id name, id (^call)(void)) {
    void *previous = sScopeName;
    __attribute__((objc_precise_lifetime)) NSString *held = nil;
    @try {
        if (!previous) {
            @try { if ([name isKindOfClass:NSString.class]) held = [name copy]; }
            @catch (__unused NSException *exception) { WCKSVGDiagnostic(@"nameScope", @"名称上下文不可用"); }
            sScopeName = (__bridge void *)held;
        }
        return call(); // Exactly one call; config and the returned object are untouched.
    } @finally { sScopeName = previous; }
}
static id WCKSVGConfig(id c, SEL s, id name, id config) {
    return WCKSVGNameScope(name, ^{ return sOriginalConfig(c, s, name, config); });
}
static id WCKSVGFile(id c, SEL s, id file, CGSize size, id color, double alpha, double rotate) {
    return WCKSVGNameScope(file, ^{ return sOriginalFile(c, s, file, size, color, alpha, rotate); });
}
static id WCKSVGAdapted(id c, SEL s, id name, id data, id config) {
    return WCKSVGNameScope(name, ^{ return sOriginalAdapted(c, s, name, data, config); });
}

static BOOL WCKSVGChoose(WCKSVGRequest *request, UITraitCollection *traits, BOOL *tinted, uint32_t *rgb) {
    *tinted = NO; *rgb = 0;
    @try {
        if (request && traits && WCKEnabled(@"svgTint"))
            *tinted = WCKSVGSelectRGB(WCKSettings.shared.snapshot, request.name,
                traits.userInterfaceStyle == UIUserInterfaceStyleDark, rgb);
        return YES;
    } @catch (__unused NSException *exception) {
        *tinted = NO; *rgb = 0; WCKSVGDiagnostic(@"selection", @"颜色选择异常；保留原调用"); return NO;
    }
}
static UIColor *WCKSVGColor(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0
        blue:(rgb & 255) / 255.0 alpha:1];
}
static id WCKSVGCall(WCKSVGKind kind, IMP original, id receiver, SEL selector, id payload,
    CGSize size, id color, double scale, double rotation, double opacity, int angle, BOOL ignore) {
    if (kind == WCKSVGTheme)
        return ((WCKThemeIMP)original)(receiver, selector, payload, size, color, opacity, angle, ignore);
    return ((WCKEngineIMP)original)(receiver, selector, payload, size, scale, rotation, opacity, color);
}
static id WCKSVGFactory(WCKSVGKind kind, IMP original, id receiver, SEL selector, id payload,
    CGSize size, id color, double scale, double rotation, double opacity, int angle, BOOL ignore) {
    BOOL top = sFactoryDepth++ == 0;
    @try {
        WCKSVGRequest *request = nil;
        id chosen = color; BOOL tinted = NO; uint32_t rgb = 0;
        if (top) {
            @try {
                BOOL valid = kind == WCKSVGEngine ? [payload isKindOfClass:NSData.class] :
                    [payload isKindOfClass:NSString.class];
                if (valid && (!color || [color isKindOfClass:UIColor.class])) {
                    NSString *name = (__bridge NSString *)sScopeName;
                    if (!name) name = kind == WCKSVGEngine ? @"<svg-data>" : payload;
                    request = [[WCKSVGRequest alloc] initWithKind:kind receiver:receiver selector:selector
                        original:original payload:payload name:name color:color size:size scale:scale
                        rotation:rotation opacity:opacity angle:angle ignore:ignore];
                    // No live traits/view access on background factories; still record for the carrier.
                    if (NSThread.isMainThread && WCKSVGChoose(request,
                        UITraitCollection.currentTraitCollection, &tinted, &rgb) && tinted)
                        chosen = WCKSVGColor(rgb);
                    if (!chosen && tinted) { chosen = color; tinted = NO; }
                } else WCKSVGDiagnostic(@"request", @"参数类型不可记录；原样调用");
            } @catch (__unused NSException *exception) {
                chosen = color; tinted = NO; WCKSVGDiagnostic(@"request", @"参数记录异常；原样调用");
            }
        }
        // Business exceptions propagate. Only a nil result with a replacement color
        // permits the one explicit retry; never retry a throwing original.
        id result = WCKSVGCall(kind, original, receiver, selector, payload, size, chosen,
            scale, rotation, opacity, angle, ignore);
        if (!result && tinted) {
            tinted = NO;
            result = WCKSVGCall(kind, original, receiver, selector, payload, size, color,
                scale, rotation, opacity, angle, ignore);
        }
        if (request) {
            @try { WCKSVGStore(result, [[WCKSVGStamp alloc] initWithRequest:request steps:@[] tinted:tinted rgb:rgb], nil); }
            @catch (__unused NSException *exception) { WCKSVGDiagnostic(@"provenance", @"来源记录异常"); }
        }
        return result; // The exact original-factory result, including non-UIImage and nil.
    } @finally { --sFactoryDepth; }
}
static id WCKSVGThemeFactory(id c, SEL s, id name, CGSize size, id color, double alpha, int angle, BOOL ignore) {
    return WCKSVGFactory(WCKSVGTheme, (IMP)sOriginalTheme, c, s, name, size, color, 1, 0, alpha, angle, ignore);
}
static id WCKSVGVMFactory(id c, SEL s, id name, CGSize size, double scale, double rotation, double opacity, id color) {
    return WCKSVGFactory(WCKSVGVM, (IMP)sOriginalVM, c, s, name, size, color, scale, rotation, opacity, 0, NO);
}
static id WCKSVGEngineFactory(id c, SEL s, id data, CGSize size, double scale, double rotation, double opacity, id color) {
    return WCKSVGFactory(WCKSVGEngine, (IMP)sOriginalEngine, c, s, data, size, color, scale, rotation, opacity, 0, NO);
}

static id WCKSVGApply(id image, WCKSVGOperation operation, UIEdgeInsets insets, NSInteger mode) {
    switch (operation) {
        case WCKSVGModeOp: return sOriginalMode ? sOriginalMode(image, @selector(imageWithRenderingMode:), mode) : nil;
        case WCKSVGInsetsOp: return sOriginalInsets ? sOriginalInsets(image, @selector(resizableImageWithCapInsets:), insets) : nil;
        case WCKSVGResizeOp: return sOriginalResize ? sOriginalResize(image,
            @selector(resizableImageWithCapInsets:resizingMode:), insets, mode) : nil;
        case WCKSVGAlignOp: return sOriginalAlign ? sOriginalAlign(image, @selector(imageWithAlignmentRectInsets:), insets) : nil;
    }
    return nil;
}
static id WCKSVGTransform(id image, WCKSVGOperation operation, UIEdgeInsets insets, NSInteger mode) {
    WCKSVGStamp *input = !sFactoryDepth && !sTransformDepth ? WCKSVGLookup(image) : nil;
    id result;
    ++sTransformDepth;
    @try { result = WCKSVGApply(image, operation, insets, mode); }
    @finally { --sTransformDepth; }
    // Preserve the first explicit request even when UIKit returns self: a
    // factory replay under another color may otherwise have different metadata.
    // Only a repeated identical last operation can be coalesced for return-self.
    // The actual host operation above still ran exactly once.
    if (input && !input.ambiguous) {
        @try {
            WCKSVGStep *last = input.steps.lastObject;
            if (result == image && last && last.operation == operation && last.mode == mode &&
                UIEdgeInsetsEqualToEdgeInsets(last.insets, insets)) return result;
            WCKSVGStep *step = [[WCKSVGStep alloc] initWithOperation:operation insets:insets mode:mode];
            WCKSVGStamp *next = [[WCKSVGStamp alloc] initWithRequest:input.request
                steps:[input.steps arrayByAddingObject:step] tinted:input.tinted rgb:input.rgb];
            WCKSVGStore(result, next, result == image ? input : nil);
        } @catch (__unused NSException *exception) { WCKSVGDiagnostic(@"transform", @"变换来源记录异常"); }
    }
    return result;
}
static id WCKSVGMode(id image, SEL cmd, UIImageRenderingMode mode) {
    return WCKSVGTransform(image, WCKSVGModeOp, UIEdgeInsetsZero, mode);
}
static id WCKSVGInsets(id image, SEL cmd, UIEdgeInsets insets) {
    return WCKSVGTransform(image, WCKSVGInsetsOp, insets, 0);
}
static id WCKSVGResize(id image, SEL cmd, UIEdgeInsets insets, UIImageResizingMode mode) {
    return WCKSVGTransform(image, WCKSVGResizeOp, insets, mode);
}
static id WCKSVGAlign(id image, SEL cmd, UIEdgeInsets insets) {
    return WCKSVGTransform(image, WCKSVGAlignOp, insets, 0);
}

// Replayed operations use normal dispatch, preserving class-cluster/subclass
// overrides and later hooks. Only the first intercepted call uses the saved IMP.
static UIImage *WCKSVGReplayStep(UIImage *image, WCKSVGStep *step) {
    ++sTransformDepth;
    @try {
        switch (step.operation) {
            case WCKSVGModeOp: return [image imageWithRenderingMode:step.mode];
            case WCKSVGInsetsOp: return [image resizableImageWithCapInsets:step.insets];
            case WCKSVGResizeOp: return [image resizableImageWithCapInsets:step.insets resizingMode:step.mode];
            case WCKSVGAlignOp: return [image imageWithAlignmentRectInsets:step.insets];
        }
        return nil;
    } @finally { --sTransformDepth; }
}
static UIImage *WCKSVGRender(WCKSVGStamp *stamp, UIImage *current, UITraitCollection *traits,
                            WCKSVGStamp **applied) {
    *applied = stamp;
    @try {
        BOOL tinted = NO; uint32_t rgb = 0;
        if (!WCKSVGChoose(stamp.request, traits, &tinted, &rgb)) return current;
        if (tinted == stamp.tinted && (!tinted || rgb == stamp.rgb)) return current;
        WCKSVGRequest *r = stamp.request;
        id receiver = r.receiver; // Promote the weak receiver only for this invocation.
        if (!receiver || !r.original) { WCKSVGDiagnostic(@"replay", @"原工厂接收者已释放"); return current; }
        id color = tinted ? WCKSVGColor(rgb) : r.color;
        if (tinted && !color) { WCKSVGDiagnostic(@"replay", @"颜色构造失败"); return current; }
        id result;
        ++sFactoryDepth;
        @try {
            result = WCKSVGCall(r.kind, r.original, receiver, r.selector, r.payload, r.size,
                color, r.scale, r.rotation, r.opacity, r.angle, r.ignore);
            if (!result && tinted) {
                tinted = NO;
                result = WCKSVGCall(r.kind, r.original, receiver, r.selector, r.payload, r.size,
                    r.color, r.scale, r.rotation, r.opacity, r.angle, r.ignore);
            }
            for (WCKSVGStep *step in stamp.steps) {
                if (![result isKindOfClass:UIImage.class]) break;
                result = WCKSVGReplayStep((UIImage *)result, step);
            }
        } @finally { --sFactoryDepth; }
        if (![result isKindOfClass:UIImage.class]) {
            WCKSVGDiagnostic(@"replay", @"重放未返回图像；保留当前图"); return current;
        }
        WCKSVGStamp *next = WCKSVGStore(result, [[WCKSVGStamp alloc] initWithRequest:r
            steps:stamp.steps tinted:tinted rgb:rgb], nil);
        if (!next) return current;
        *applied = next; return result;
    } @catch (__unused NSException *exception) {
        // This is an ancillary refresh, NOT the caller's initial factory/transform.
        WCKSVGDiagnostic(@"replay", @"重放异常；保留当前图"); return current;
    }
}

static WCKSVGDriver *WCKDriver(UIView *view, BOOL create) {
    WCKSVGDriver *driver = objc_getAssociatedObject(view, &sDriverKey);
    if (!driver && create) {
        driver = [WCKSVGDriver new]; driver.states = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(view, &sDriverKey, driver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return driver;
}
static void WCKTrack(UIView *view, WCKSVGDriver *driver) {
    if (driver.normal || driver.highlighted || driver.states.count) {
        if (!sSVGViews) sSVGViews = [NSHashTable weakObjectsHashTable];
        [sSVGViews addObject:view];
    } else {
        [sSVGViews removeObject:view];
        objc_setAssociatedObject(view, &sDriverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static WCKSVGSlot *WCKSVGGetSlot(WCKSVGDriver *driver, WCKSVGSlotKind kind, UIControlState state) {
    if (kind == WCKSVGButton) return driver.states[@(state)];
    return kind == WCKSVGHighlighted ? driver.highlighted : driver.normal;
}
static void WCKSVGPutSlot(WCKSVGDriver *driver, WCKSVGSlotKind kind, UIControlState state, WCKSVGSlot *slot) {
    if (kind == WCKSVGButton) {
        if (slot) driver.states[@(state)] = slot;
        else [driver.states removeObjectForKey:@(state)];
    } else if (kind == WCKSVGHighlighted) driver.highlighted = slot;
    else driver.normal = slot;
}
static UIImage *WCKSVGCurrent(id view, WCKSVGSlotKind kind, UIControlState state) {
    if (kind == WCKSVGButton) return [(UIButton *)view imageForState:state];
    return kind == WCKSVGHighlighted ? [(UIImageView *)view highlightedImage] : [(UIImageView *)view image];
}
static void WCKSVGAssign(id view, WCKSVGSlotKind kind, UIControlState state, UIImage *image) {
    if (kind == WCKSVGButton) sOriginalButton(view, @selector(setImage:forState:), image, state);
    else if (kind == WCKSVGHighlighted) sOriginalHighlighted(view, @selector(setHighlightedImage:), image);
    else sOriginalImage(view, @selector(setImage:), image);
}
static void WCKSVGSet(id view, UIImage *image, WCKSVGSlotKind kind, UIControlState state) {
    if (!NSThread.isMainThread) { WCKSVGAssign(view, kind, state, image); return; }
    if (sAssignmentScope && sAssignmentScope->view == view && sAssignmentScope->kind == kind &&
        (kind != WCKSVGButton || sAssignmentScope->state == state)) sAssignmentScope->superseded = YES;
    if (sViewDepth || sFactoryDepth) { WCKSVGAssign(view, kind, state, image); return; }
    WCKSVGAssignmentScope scope = {view, kind, state, NO};
    WCKSVGAssignmentScope *previousScope = sAssignmentScope;
    sAssignmentScope = &scope;
    ++sViewDepth;
    @try {
        UIImage *next = image, *entryImage = nil; WCKSVGStamp *stamp = nil;
        BOOL observedEntry = NO;
        @try {
            // Incoming image has not been assigned yet. Compare against entry
            // state, never against the incoming argument itself.
            entryImage = WCKSVGCurrent(view, kind, state); observedEntry = YES;
            stamp = WCKSVGLookup(image);
            if (stamp.ambiguous) stamp = nil;
            WCKSVGDriver *driver = WCKDriver(view, NO);
            if (stamp && kind == WCKSVGButton && !driver.states[@(state)] &&
                driver.states.count >= WCKSVGMaximumButtonStates) {
                stamp = nil; WCKSVGDiagnostic(@"states", @"按钮状态超过32；原样赋值，不新增跟踪");
            }
            if (stamp) next = WCKSVGRender(stamp, image, [view traitCollection], &stamp);
        } @catch (__unused NSException *exception) {
            next = image; stamp = nil; WCKSVGDiagnostic(@"prepare", @"槽位准备异常；原样赋值");
        }
        BOOL superseded = scope.superseded;
        @try { if (observedEntry && WCKSVGCurrent(view, kind, state) != entryImage) superseded = YES; }
        @catch (__unused NSException *exception) { superseded = YES; }
        if (superseded || scope.superseded) {
            // The host's newer assignment wins. Do not call the pending original
            // setter after replay has replaced its target, including ABA reentry.
            @try {
                WCKSVGDriver *driver = WCKDriver(view, NO);
                if (driver) { WCKSVGPutSlot(driver, kind, state, nil); WCKTrack(view, driver); }
            } @catch (__unused NSException *exception) { WCKSVGDiagnostic(@"slot", @"失效槽位清理异常"); }
            return;
        }
        WCKSVGAssign(view, kind, state, next); // Initial setter exceptions must propagate.
        @try {
            WCKSVGSlot *slot = nil;
            if (stamp && WCKSVGCurrent(view, kind, state) == next && !scope.superseded) {
                slot = [WCKSVGSlot new]; slot.stamp = stamp; slot.last = next;
            }
            WCKSVGDriver *driver = WCKDriver(view, slot != nil);
            if (driver) { WCKSVGPutSlot(driver, kind, state, slot); WCKTrack(view, driver); }
        } @catch (__unused NSException *exception) { WCKSVGDiagnostic(@"slot", @"槽位记录异常"); }
    } @finally { sAssignmentScope = previousScope; --sViewDepth; }
}
static void WCKSVGSetImage(id view, SEL cmd, UIImage *image) { WCKSVGSet(view, image, WCKSVGNormal, 0); }
static void WCKSVGSetHighlighted(id view, SEL cmd, UIImage *image) { WCKSVGSet(view, image, WCKSVGHighlighted, 0); }
static void WCKSVGSetButton(id view, SEL cmd, UIImage *image, UIControlState state) { WCKSVGSet(view, image, WCKSVGButton, state); }

// Resolve the recipe this slot may replay for `current`. Another caller can
// append an explicit transform to the same cached UIImage object (return-self),
// leaving a longer recipe in the table. Adopting that superset is only sound
// when this slot's operations are an exact prefix, because replay then applies
// both callers' transforms in the order they really happened. Anything else
// stays fail-closed: no ownership, no automatic refresh.
static WCKSVGStamp *WCKSVGOwnedStamp(UIImage *current, WCKSVGSlot *slot) {
    if (!current || current != slot.last) return nil;
    WCKSVGStamp *observed = WCKSVGLookup(current);
    if (!observed || observed.ambiguous || observed.tinted != slot.stamp.tinted ||
        observed.rgb != slot.stamp.rgb ||
        !WCKSVGSameRequest(observed.request, slot.stamp.request)) return nil;
    NSArray<WCKSVGStep *> *mine = slot.stamp.steps, *theirs = observed.steps;
    if (theirs.count < mine.count) return nil;
    for (NSUInteger i = 0; i < mine.count; ++i) {
        WCKSVGStep *x = mine[i], *y = theirs[i];
        if (x.operation != y.operation || x.mode != y.mode ||
            !UIEdgeInsetsEqualToEdgeInsets(x.insets, y.insets)) return nil;
    }
    return observed;
}
static void WCKSVGRefreshSlot(id view, WCKSVGDriver *driver, WCKSVGSlotKind kind, UIControlState state) {
    WCKSVGSlot *slot = WCKSVGGetSlot(driver, kind, state);
    if (!slot) return;
    @try {
        UIImage *current = WCKSVGCurrent(view, kind, state);
        WCKSVGStamp *owned = WCKSVGOwnedStamp(current, slot);
        if (!owned) { WCKSVGPutSlot(driver, kind, state, nil); return; }
        WCKSVGStamp *applied = nil;
        UIImage *next = WCKSVGRender(owned, current, [view traitCollection], &applied);
        if (next == current) return;
        // Replay can execute arbitrary saved IMPs. Recheck after those callbacks,
        // rather than overwriting a replacement made while they were running.
        if (WCKSVGCurrent(view, kind, state) != current || !WCKSVGOwnedStamp(current, slot)) {
            WCKSVGPutSlot(driver, kind, state, nil); return;
        }
        // Refresh is a new assignment: preserve the real view's override chain.
        // sViewDepth makes re-entry into our base-class hooks pass through once.
        if (kind == WCKSVGButton) [(UIButton *)view setImage:next forState:state];
        else if (kind == WCKSVGHighlighted) [(UIImageView *)view setHighlightedImage:next];
        else [(UIImageView *)view setImage:next];
        if (WCKSVGCurrent(view, kind, state) == next) { slot.stamp = applied; slot.last = next; }
        else WCKSVGPutSlot(driver, kind, state, nil);
    } @catch (__unused NSException *exception) { WCKSVGDiagnostic(@"refresh", @"槽位刷新异常；不继续覆盖"); }
}
static void WCKRefreshSVGView(UIView *view) {
    if (!NSThread.isMainThread || sViewDepth || sFactoryDepth) return;
    ++sViewDepth;
    @try {
        WCKSVGDriver *driver = WCKDriver(view, NO);
        if (!driver) return;
        if ([view isKindOfClass:UIImageView.class]) {
            if (sOriginalImage) WCKSVGRefreshSlot(view, driver, WCKSVGNormal, 0);
            if (sOriginalHighlighted) WCKSVGRefreshSlot(view, driver, WCKSVGHighlighted, 0);
        } else if ([view isKindOfClass:UIButton.class] && sOriginalButton) {
            for (NSNumber *state in driver.states.allKeys)
                WCKSVGRefreshSlot(view, driver, WCKSVGButton, state.unsignedIntegerValue);
        }
        WCKTrack(view, driver);
    } @catch (__unused NSException *exception) { WCKSVGDiagnostic(@"refresh", @"视图刷新异常"); }
    @finally { --sViewDepth; }
}
static void WCKSVGImageTrait(id view, SEL cmd, UITraitCollection *previous) {
    sOriginalImageTrait(view, cmd, previous); WCKRefreshSVGView(view);
}
static void WCKSVGButtonTrait(id view, SEL cmd, UITraitCollection *previous) {
    sOriginalButtonTrait(view, cmd, previous); WCKRefreshSVGView(view);
}
static void WCKSVGHookStatus(NSString *key, BOOL ready) {
    WCKSVGDiagnostic(key, ready ? @"ready" : @"ABI或hook不可用");
}

void WCKInstallSVG(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *themeArgs[] = {"@", @encode(CGSize), "@", "d", "i", "B"};
        const char *engineArgs[] = {"@", @encode(CGSize), "d", "d", "d", "@"};
        BOOL theme = WCKInstallHook(NSClassFromString(@"MMThemeManager"),
            NSSelectorFromString(@"svgImageNamed:size:color:alpha:angle:ignoreNotFound:"),
            (IMP)WCKSVGThemeFactory, (IMP *)&sOriginalTheme, "@", themeArgs, 6);
        BOOL vm = WCKInstallHook(object_getClass(NSClassFromString(@"WeSVGVM")),
            NSSelectorFromString(@"imageWithName:size:scale:rotation:opacity:color:"),
            (IMP)WCKSVGVMFactory, (IMP *)&sOriginalVM, "@", engineArgs, 6);
        BOOL engine = WCKInstallHook(object_getClass(NSClassFromString(@"WeSVGEngine")),
            NSSelectorFromString(@"imageWithData:size:scale:rotation:opacity:color:"),
            (IMP)WCKSVGEngineFactory, (IMP *)&sOriginalEngine, "@", engineArgs, 6);
        WCKSVGHookStatus(@"theme", theme); WCKSVGHookStatus(@"vm", vm); WCKSVGHookStatus(@"engine", engine);

        // Naming context only: the host's named/file paths may erase name before
        // calling the data engine. Do not replay config or substitute name for data.
        Class svg = object_getClass(NSClassFromString(@"WCSVGImage"));
        const char *configArgs[] = {"@", "@"}, *adaptedArgs[] = {"@", "@", "@"};
        const char *fileArgs[] = {"@", @encode(CGSize), "@", "d", "d"};
        BOOL config = WCKInstallHook(svg, NSSelectorFromString(@"imageNamed:fromConfig:"),
            (IMP)WCKSVGConfig, (IMP *)&sOriginalConfig, "@", configArgs, 2);
        BOOL file = WCKInstallHook(svg, NSSelectorFromString(@"imageWithContentsOfFile:size:color:alpha:rotate:"),
            (IMP)WCKSVGFile, (IMP *)&sOriginalFile, "@", fileArgs, 5);
        BOOL adapted = WCKInstallHook(svg, NSSelectorFromString(@"adaptedWeSVGImageWithName:data:config:"),
            (IMP)WCKSVGAdapted, (IMP *)&sOriginalAdapted, "@", adaptedArgs, 3);
        WCKSVGHookStatus(@"config", config); WCKSVGHookStatus(@"file", file); WCKSVGHookStatus(@"adapted", adapted);
        WCKSetModuleStatus(@"svgTint.nameScope", config && file && adapted ? @"ready" : @"部分名称上下文不可用");

        const char *modeArgs[] = {@encode(UIImageRenderingMode)};
        const char *insetArgs[] = {@encode(UIEdgeInsets)};
        const char *resizeArgs[] = {@encode(UIEdgeInsets), @encode(UIImageResizingMode)};
        BOOL mode = WCKInstallHook(UIImage.class, @selector(imageWithRenderingMode:),
            (IMP)WCKSVGMode, (IMP *)&sOriginalMode, "@", modeArgs, 1);
        BOOL insets = WCKInstallHook(UIImage.class, @selector(resizableImageWithCapInsets:),
            (IMP)WCKSVGInsets, (IMP *)&sOriginalInsets, "@", insetArgs, 1);
        BOOL resize = WCKInstallHook(UIImage.class, @selector(resizableImageWithCapInsets:resizingMode:),
            (IMP)WCKSVGResize, (IMP *)&sOriginalResize, "@", resizeArgs, 2);
        BOOL align = WCKInstallHook(UIImage.class, @selector(imageWithAlignmentRectInsets:),
            (IMP)WCKSVGAlign, (IMP *)&sOriginalAlign, "@", insetArgs, 1);
        WCKSetModuleStatus(@"svgTint.transforms", mode && insets && resize && align ? @"ready" : @"部分图像变换来源保留不可用");
        const char *imageArgs[] = {"@"};
        const char *buttonArgs[] = {"@", @encode(UIControlState)};
        BOOL image = WCKInstallHook(UIImageView.class, @selector(setImage:),
            (IMP)WCKSVGSetImage, (IMP *)&sOriginalImage, "v", imageArgs, 1);
        BOOL highlighted = WCKInstallHook(UIImageView.class, @selector(setHighlightedImage:),
            (IMP)WCKSVGSetHighlighted, (IMP *)&sOriginalHighlighted, "v", imageArgs, 1);
        BOOL button = WCKInstallHook(UIButton.class, @selector(setImage:forState:),
            (IMP)WCKSVGSetButton, (IMP *)&sOriginalButton, "v", buttonArgs, 2);
        BOOL imageTrait = WCKInstallHook(UIImageView.class, @selector(traitCollectionDidChange:),
            (IMP)WCKSVGImageTrait, (IMP *)&sOriginalImageTrait, "v", imageArgs, 1);
        BOOL buttonTrait = WCKInstallHook(UIButton.class, @selector(traitCollectionDidChange:),
            (IMP)WCKSVGButtonTrait, (IMP *)&sOriginalButtonTrait, "v", imageArgs, 1);
        WCKSVGHookStatus(@"imageView", image); WCKSVGHookStatus(@"highlighted", highlighted);
        WCKSVGHookStatus(@"button", button); WCKSVGHookStatus(@"imageTrait", imageTrait);
        WCKSVGHookStatus(@"buttonTrait", buttonTrait);
        WCKSetModuleStatus(@"svgTint.refresh", image && highlighted && button && imageTrait && buttonTrait
            ? @"ready" : @"部分即时刷新不可用；可重新打开页面");
        if (image || highlighted || button) {
            sSettingsObserver = [NSNotificationCenter.defaultCenter
                addObserverForName:WCKSettingsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *notification) {
                    @try { for (UIView *view in sSVGViews.allObjects) WCKRefreshSVGView(view); }
                    @catch (__unused NSException *exception) { WCKSVGDiagnostic(@"refresh", @"刷新通知处理异常"); }
                }];
        }
        // Optional refresh/name-scope failures do not disable valid canonical hooks.
        // This says at least one factory is usable, NOT that all routes are covered.
        WCKSetModuleStatus(@"svgTint", theme || vm || engine ? @"ready" : @"SVG工厂不可用");
    });
}
