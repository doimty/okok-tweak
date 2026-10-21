#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKSVGSelection.h"

// Only factory outputs are tagged. Neither a cached source nor the caller's config
// is ever modified. A descriptor owns the raw source, never its tagged derivative.
@interface WCKSVGDescriptor : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, strong) UIImage *source;
@end
@implementation WCKSVGDescriptor
@end

@interface WCKSVGDriver : NSObject
@property(nonatomic, weak) UIView *host;
@property(nonatomic, strong) WCKSVGDescriptor *normal;
@property(nonatomic, strong) WCKSVGDescriptor *highlighted;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, WCKSVGDescriptor *> *states;
@end
@implementation WCKSVGDriver
@end

static char sDescriptorKey, sDriverKey;
static NSHashTable<UIView *> *sSVGViews; // main-thread only, weak
static id sSettingsObserver;
static _Thread_local NSUInteger sFactoryDepth;
static _Thread_local NSUInteger sViewDepth;
static const NSUInteger WCKSVGMaximumButtonStates = 32;
static id (*sOriginalNamed)(id, SEL, id, CGSize, id, double, double);
static id (*sOriginalFile)(id, SEL, id, CGSize, id, double, double);
static id (*sOriginalConfig)(id, SEL, id, id);
static id (*sOriginalAdapted)(id, SEL, id, id, id);
static id (*sOriginalData)(id, SEL, id, id);
static id (*sOriginalSimple)(id, SEL, id);
static id (*sOriginalColor)(id, SEL, id, id);
static id (*sOriginalAlpha)(id, SEL, id, id, double);
static id (*sOriginalRotate)(id, SEL, id, id, double, double);
static id (*sOriginalSize)(id, SEL, id, CGSize);
static id (*sOriginalSizeColor)(id, SEL, id, CGSize, id);
static id (*sOriginalResizeData)(id, SEL, id, CGSize, double);
static id (*sOriginalMode)(id, SEL, UIImageRenderingMode);
static id (*sOriginalInsets)(id, SEL, UIEdgeInsets);
static id (*sOriginalResize)(id, SEL, UIEdgeInsets, UIImageResizingMode);
static id (*sOriginalAlign)(id, SEL, UIEdgeInsets);
static _Thread_local NSUInteger sTransformDepth;
static void (*sOriginalImage)(id, SEL, UIImage *);
static void (*sOriginalHighlighted)(id, SEL, UIImage *);
static void (*sOriginalButton)(id, SEL, UIImage *, UIControlState);
static void (*sOriginalImageTrait)(id, SEL, UITraitCollection *);
static void (*sOriginalButtonTrait)(id, SEL, UITraitCollection *);

static WCKSVGDescriptor *WCKDescriptor(id image) {
    if (![image isKindOfClass:UIImage.class]) return nil;
    return objc_getAssociatedObject(image, &sDescriptorKey);
}

static UIImage *WCKSVGCopy(UIImage *source) {
    if (!source.CGImage || source.images.count) return nil;
    UIImage *copy = [[UIImage alloc] initWithCGImage:source.CGImage
        scale:source.scale orientation:source.imageOrientation];
    copy = [copy resizableImageWithCapInsets:source.capInsets resizingMode:source.resizingMode];
    copy = [copy imageWithAlignmentRectInsets:source.alignmentRectInsets];
    return [copy imageWithRenderingMode:source.renderingMode];
}

static UIImage *WCKSVGRender(WCKSVGDescriptor *descriptor, UITraitCollection *traits,
                            BOOL factory) {
    UIImage *source = descriptor.source;
    @try {
        uint32_t rgb = 0;
        // WCKEnabled includes the real host and ready-module gates. Selection
        // additionally validates a single immutable snapshot. Never open a switch.
        BOOL tint = traits && WCKEnabled(@"svgTint") &&
            WCKSVGSelectRGB(WCKSettings.shared.snapshot, descriptor.name,
                traits.userInterfaceStyle == UIUserInterfaceStyleDark, &rgb);
        // Keep provenance even when disabled: a host reassigning view.image must not
        // orphan the SVG and prevent the next enable from repainting it.
        (void)factory;
        UIImage *image = WCKSVGCopy(source);
        if (!image || image == source) return source;
        if (tint) {
            UIColor *color = [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
            image = [image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
            if (!image || image == source) return source;
            // Tinting must also preserve slicing and alignment metadata.
            image = [image resizableImageWithCapInsets:source.capInsets resizingMode:source.resizingMode];
            image = [image imageWithAlignmentRectInsets:source.alignmentRectInsets];
        }
        objc_setAssociatedObject(image, &sDescriptorKey, descriptor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return image;
    } @catch (__unused NSException *exception) { return source; }
}

static id WCKSVGRecord(id result, id name) {
    @try {
        if (![result isKindOfClass:UIImage.class]) return result;
        WCKSVGDescriptor *existing = WCKDescriptor(result);
        UIImage *source = existing ? existing.source : result;
        if (!source.CGImage || source.images.count) return result;
        WCKSVGDescriptor *descriptor = [WCKSVGDescriptor new];
        descriptor.name = [name isKindOfClass:NSString.class] ? name : @"<svg-data>";
        descriptor.source = source;
        // Off-main factories only tag: the eventual carrier's traits decide color.
        UITraitCollection *traits = NSThread.isMainThread ? UITraitCollection.currentTraitCollection : nil;
        return WCKSVGRender(descriptor, traits, YES);
    } @catch (__unused NSException *exception) { return result; }
}

// Depth protects original factory-to-factory calls from seeing our tinted images.
// Original exceptions are not swallowed; finally always restores TLS nesting.
static id WCKSVGNamed(id cls, SEL cmd, id name, CGSize size, id color, double alpha, double rotate) {
    BOOL top = sFactoryDepth++ == 0; id result;
    @try { result = sOriginalNamed(cls, cmd, name, size, color, alpha, rotate); }
    @finally { --sFactoryDepth; }
    return top ? WCKSVGRecord(result, name) : result;
}
static id WCKSVGFile(id cls, SEL cmd, id file, CGSize size, id color, double alpha, double rotate) {
    BOOL top = sFactoryDepth++ == 0; id result;
    @try { result = sOriginalFile(cls, cmd, file, size, color, alpha, rotate); }
    @finally { --sFactoryDepth; }
    return top ? WCKSVGRecord(result, file) : result;
}
static id WCKSVGConfig(id cls, SEL cmd, id name, id config) {
    BOOL top = sFactoryDepth++ == 0; id result;
    @try { result = sOriginalConfig(cls, cmd, name, config); }
    @finally { --sFactoryDepth; }
    return top ? WCKSVGRecord(result, name) : result;
}
static id WCKSVGAdapted(id cls, SEL cmd, id name, id data, id config) {
    BOOL top = sFactoryDepth++ == 0; id result;
    @try { result = sOriginalAdapted(cls, cmd, name, data, config); }
    @finally { --sFactoryDepth; }
    return top ? WCKSVGRecord(result, name) : result;
}
static id WCKSVGData(id cls, SEL cmd, id data, id config) {
    BOOL top = sFactoryDepth++ == 0; id result;
    @try { result = sOriginalData(cls, cmd, data, config); }
    @finally { --sFactoryDepth; }
    return top ? WCKSVGRecord(result, @"<svg-data>") : result;
}

// Cover convenience factories independently: other plugins can replace a short
// overload without forwarding to the full-size overload. Never tag svgDataWithName:.
#define WCK_FACTORY_BODY(call, icon) \
    BOOL top = sFactoryDepth++ == 0; id result; \
    @try { result = (call); } @finally { --sFactoryDepth; } \
    return top ? WCKSVGRecord(result, (icon)) : result
static id WCKSVGSimple(id c, SEL s, id n) { WCK_FACTORY_BODY(sOriginalSimple(c,s,n), n); }
static id WCKSVGColor(id c, SEL s, id n, id color) { WCK_FACTORY_BODY(sOriginalColor(c,s,n,color), n); }
static id WCKSVGAlpha(id c, SEL s, id n, id color, double a) { WCK_FACTORY_BODY(sOriginalAlpha(c,s,n,color,a), n); }
static id WCKSVGRotate(id c, SEL s, id n, id color, double a, double r) { WCK_FACTORY_BODY(sOriginalRotate(c,s,n,color,a,r), n); }
static id WCKSVGSize(id c, SEL s, id n, CGSize size) { WCK_FACTORY_BODY(sOriginalSize(c,s,n,size), n); }
static id WCKSVGSizeColor(id c, SEL s, id n, CGSize size, id color) { WCK_FACTORY_BODY(sOriginalSizeColor(c,s,n,size,color), n); }
static id WCKSVGResizeData(id c, SEL s, id data, CGSize size, double scale) { WCK_FACTORY_BODY(sOriginalResizeData(c,s,data,size,scale), @"<svg-data>"); }
#undef WCK_FACTORY_BODY

// UIImage returns a new object for these operations and drops associated objects.
// Propagate only proven SVG provenance, from an independently transformed raw
// source. Untagged photos/avatars take exactly their original path.
#define WCK_TRANSFORM_BODY(call) \
    WCKSVGDescriptor *descriptor = !sTransformDepth ? WCKDescriptor(image) : nil; \
    if (!descriptor) return (call); \
    image = descriptor.source; id result; ++sTransformDepth; \
    @try { result = (call); } @finally { --sTransformDepth; } \
    return WCKSVGRecord(result, descriptor.name)
static id WCKSVGMode(id image, SEL cmd, UIImageRenderingMode mode) {
    WCK_TRANSFORM_BODY(sOriginalMode(image,cmd,mode));
}
static id WCKSVGInsets(id image, SEL cmd, UIEdgeInsets insets) {
    WCK_TRANSFORM_BODY(sOriginalInsets(image,cmd,insets));
}
static id WCKSVGResize(id image, SEL cmd, UIEdgeInsets insets, UIImageResizingMode mode) {
    WCK_TRANSFORM_BODY(sOriginalResize(image,cmd,insets,mode));
}
static id WCKSVGAlign(id image, SEL cmd, UIEdgeInsets insets) {
    WCK_TRANSFORM_BODY(sOriginalAlign(image,cmd,insets));
}
#undef WCK_TRANSFORM_BODY

static WCKSVGDriver *WCKDriver(UIView *view, BOOL create) {
    WCKSVGDriver *driver = objc_getAssociatedObject(view, &sDriverKey);
    if (!driver && create) {
        driver = [WCKSVGDriver new]; driver.host = view;
        driver.states = [NSMutableDictionary dictionary];
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

static UIImage *WCKPrepareImage(UIView *view, UIImage *image, BOOL highlighted,
                               BOOL button, UIControlState state) {
    // UIKit setters are main-thread API. Do not introduce off-main UI access.
    if (!NSThread.isMainThread || sViewDepth) return image;
    @try {
        WCKSVGDescriptor *descriptor = WCKDescriptor(image);
        WCKSVGDriver *driver = WCKDriver(view, descriptor != nil);
        if (!driver) return image; // Unrelated photos/avatars stay untouched.
        if (button) {
            NSNumber *key = @(state);
            if (descriptor && !driver.states[key] && driver.states.count >= WCKSVGMaximumButtonStates)
                return descriptor.source; // No untracked tint that cannot be undone.
            if (descriptor) driver.states[key] = descriptor;
            else [driver.states removeObjectForKey:key];
        } else if (highlighted) driver.highlighted = descriptor;
        else driver.normal = descriptor;
        WCKTrack(view, driver);
        return descriptor ? WCKSVGRender(descriptor, view.traitCollection, NO) : image;
    } @catch (__unused NSException *exception) { return image; }
}

static void WCKSVGSetImage(id view, SEL cmd, UIImage *image) {
    UIImage *next = WCKPrepareImage(view, image, NO, NO, 0);
    ++sViewDepth;
    @try { sOriginalImage(view, cmd, next); }
    @finally { --sViewDepth; }
}
static void WCKSVGSetHighlighted(id view, SEL cmd, UIImage *image) {
    UIImage *next = WCKPrepareImage(view, image, YES, NO, 0);
    ++sViewDepth;
    @try { sOriginalHighlighted(view, cmd, next); }
    @finally { --sViewDepth; }
}
static void WCKSVGSetButton(id view, SEL cmd, UIImage *image, UIControlState state) {
    UIImage *next = WCKPrepareImage(view, image, NO, YES, state);
    ++sViewDepth;
    @try { sOriginalButton(view, cmd, next, state); }
    @finally { --sViewDepth; }
}

static void WCKRefreshSVGView(UIView *view) {
    if (!NSThread.isMainThread || sViewDepth) return;
    WCKSVGDriver *driver = WCKDriver(view, NO);
    if (!driver) return;
    ++sViewDepth;
    @try {
        // Invoke the preserved IMP chain, not a global UIImage/UIAppearance hook.
        if ([view isKindOfClass:UIImageView.class]) {
            if (driver.normal && sOriginalImage)
                sOriginalImage(view, @selector(setImage:), WCKSVGRender(driver.normal, view.traitCollection, NO));
            if (driver.highlighted && sOriginalHighlighted)
                sOriginalHighlighted(view, @selector(setHighlightedImage:), WCKSVGRender(driver.highlighted, view.traitCollection, NO));
        } else if ([view isKindOfClass:UIButton.class] && sOriginalButton) {
            for (NSNumber *state in driver.states.allKeys) {
                UIImage *image = WCKSVGRender(driver.states[state], view.traitCollection, NO);
                sOriginalButton(view, @selector(setImage:forState:), image, state.unsignedIntegerValue);
            }
        }
    } @finally { --sViewDepth; }
}
static void WCKSVGImageTrait(id view, SEL cmd, UITraitCollection *previous) {
    sOriginalImageTrait(view, cmd, previous);
    WCKRefreshSVGView(view);
}
static void WCKSVGButtonTrait(id view, SEL cmd, UITraitCollection *previous) {
    sOriginalButtonTrait(view, cmd, previous);
    WCKRefreshSVGView(view);
}

static void WCKSVGHookStatus(NSString *key, BOOL ready) {
    // Fixed selector identifiers only: never record icon names, paths or chat data.
    WCKSetModuleStatus([@"svgTint.debug." stringByAppendingString:key], ready ? @"ready" : @"ABI或hook不可用");
}

void WCKInstallSVG(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = object_getClass(NSClassFromString(@"WCSVGImage"));
        const char *sizedArgs[] = {"@", @encode(CGSize), "@", "d", "d"};
        const char *configArgs[] = {"@", "@"};
        const char *adaptedArgs[] = {"@", "@", "@"};
        BOOL named = WCKInstallHook(cls, NSSelectorFromString(@"imageNamed:size:color:alpha:rotate:"),
            (IMP)WCKSVGNamed, (IMP *)&sOriginalNamed, "@", sizedArgs, 5);
        BOOL file = WCKInstallHook(cls, NSSelectorFromString(@"imageWithContentsOfFile:size:color:alpha:rotate:"),
            (IMP)WCKSVGFile, (IMP *)&sOriginalFile, "@", sizedArgs, 5);
        BOOL config = WCKInstallHook(cls, NSSelectorFromString(@"imageNamed:fromConfig:"),
            (IMP)WCKSVGConfig, (IMP *)&sOriginalConfig, "@", configArgs, 2);
        BOOL adapted = WCKInstallHook(cls, NSSelectorFromString(@"adaptedWeSVGImageWithName:data:config:"),
            (IMP)WCKSVGAdapted, (IMP *)&sOriginalAdapted, "@", adaptedArgs, 3);
        BOOL data = WCKInstallHook(cls, NSSelectorFromString(@"imageData:fromConfig:"),
            (IMP)WCKSVGData, (IMP *)&sOriginalData, "@", configArgs, 2);
        WCKSVGHookStatus(@"named", named); WCKSVGHookStatus(@"file", file);
        WCKSVGHookStatus(@"config", config); WCKSVGHookStatus(@"adapted", adapted);
        WCKSVGHookStatus(@"data", data);
        const char *oneObject[] = {"@"}, *objectSize[] = {"@", @encode(CGSize)};
        const char *alphaArgs[] = {"@", "@", "d"}, *rotateArgs[] = {"@", "@", "d", "d"};
        const char *sizeColorArgs[] = {"@", @encode(CGSize), "@"};
        const char *resizeDataArgs[] = {"@", @encode(CGSize), "d"};
        BOOL simple = WCKInstallHook(cls, NSSelectorFromString(@"imageNamed:"), (IMP)WCKSVGSimple,
            (IMP *)&sOriginalSimple, "@", oneObject, 1);
        BOOL color = WCKInstallHook(cls, NSSelectorFromString(@"imageNamed:color:"), (IMP)WCKSVGColor,
            (IMP *)&sOriginalColor, "@", configArgs, 2);
        BOOL alpha = WCKInstallHook(cls, NSSelectorFromString(@"imageNamed:color:alpha:"), (IMP)WCKSVGAlpha,
            (IMP *)&sOriginalAlpha, "@", alphaArgs, 3);
        BOOL rotate = WCKInstallHook(cls, NSSelectorFromString(@"imageNamed:color:alpha:rotate:"), (IMP)WCKSVGRotate,
            (IMP *)&sOriginalRotate, "@", rotateArgs, 4);
        BOOL size = WCKInstallHook(cls, NSSelectorFromString(@"imageNamed:size:"), (IMP)WCKSVGSize,
            (IMP *)&sOriginalSize, "@", objectSize, 2);
        BOOL sizeColor = WCKInstallHook(cls, NSSelectorFromString(@"imageNamed:size:color:"), (IMP)WCKSVGSizeColor,
            (IMP *)&sOriginalSizeColor, "@", sizeColorArgs, 3);
        BOOL resizeData = WCKInstallHook(cls, NSSelectorFromString(@"imageData:resize:scale:"), (IMP)WCKSVGResizeData,
            (IMP *)&sOriginalResizeData, "@", resizeDataArgs, 3);
        WCKSVGHookStatus(@"simple", simple); WCKSVGHookStatus(@"color", color);
        WCKSVGHookStatus(@"alpha", alpha); WCKSVGHookStatus(@"rotate", rotate);
        WCKSVGHookStatus(@"size", size); WCKSVGHookStatus(@"sizeColor", sizeColor);
        WCKSVGHookStatus(@"resizeData", resizeData);
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
                    for (UIView *view in sSVGViews.allObjects) WCKRefreshSVGView(view);
                }];
        }
        // A missing optional entry never disables the other validated factories.
        WCKSetModuleStatus(@"svgTint", named || file || config || adapted || data ||
            simple || color || alpha || rotate || size || sizeColor || resizeData ? @"ready" : @"SVG工厂不可用");
    });
}
