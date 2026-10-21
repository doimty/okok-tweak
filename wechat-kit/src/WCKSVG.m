#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKPolicy.h"
#import "WCKSettings.h"

static id (*sOriginalNamed)(id, SEL, id, CGSize, id, double, double);
static id (*sOriginalConfig)(id, SEL, id, id);
static BOOL sCanCloneConfig;

static UIColor *WCKColorForIcon(id name) {
    if (!WCKEnabled(@"svgTint") || ![name isKindOfClass:NSString.class]) return nil;
    NSDictionary *settings = WCKSettings.shared.snapshot;
    NSString *include = settings[@"svgInclude"], *exclude = settings[@"svgExclude"];
    if (![include isKindOfClass:NSString.class] ||
        ![exclude isKindOfClass:NSString.class] ||
        !WCKShouldTintName([name UTF8String], include.UTF8String, exclude.UTF8String)) return nil;
    BOOL dark = UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    NSString *key = dark ? @"svgTintDark" : @"svgTintLight";
    NSString *text = settings[key]; uint32_t rgb;
    if (![text isKindOfClass:NSString.class] || !WCKParseRGB(text.UTF8String, &rgb)) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 255)/255.0
        green:((rgb >> 8) & 255)/255.0 blue:(rgb & 255)/255.0 alpha:1];
}
static id WCKSVGNamed(id cls, SEL selector, id name, CGSize size, id color,
                      double alpha, double rotation) {
    UIColor *replacement = WCKColorForIcon(name);
    return sOriginalNamed(cls, selector, name, size, replacement ?: color, alpha, rotation);
}
static id WCKSVGConfig(id cls, SEL selector, id name, id config) {
    UIColor *color = WCKColorForIcon(name);
    Class configClass = NSClassFromString(@"WCSVGImageConfig");
    if (!color || !config || object_getClass(config) != configClass || !sCanCloneConfig)
        return sOriginalConfig(cls, selector, name, config);
    // Do NOT mutate a cached/shared configuration owned by WeChat or another plugin.
    CGRect bounds = ((CGRect (*)(id,SEL))objc_msgSend)(config, NSSelectorFromString(@"bounds"));
    double rotation = ((double (*)(id,SEL))objc_msgSend)(config, NSSelectorFromString(@"rotationAngle"));
    double opacity = ((double (*)(id,SEL))objc_msgSend)(config, NSSelectorFromString(@"opacity"));
    double scale = ((double (*)(id,SEL))objc_msgSend)(config, NSSelectorFromString(@"rescale"));
    SEL factory = NSSelectorFromString(@"imageConfigWithTintColor:bounds:rotationAngle:opacity:scale:");
    id copy = ((id (*)(id,SEL,id,CGRect,double,double,double))objc_msgSend)
        (configClass, factory, color, bounds, rotation, opacity, scale);
    return sOriginalConfig(cls, selector, name, copy ?: config);
}

void WCKInstallSVG(void) {
    Class cls = object_getClass(NSClassFromString(@"WCSVGImage"));
    const char *namedArgs[] = {"@", @encode(CGSize), "@", "d", "d"};
    BOOL named = WCKInstallHook(cls,
        NSSelectorFromString(@"imageNamed:size:color:alpha:rotate:"), (IMP)WCKSVGNamed,
        (IMP *)&sOriginalNamed, "@", namedArgs, 5);
    Class cfg = NSClassFromString(@"WCSVGImageConfig");
    const char *factoryArgs[] = {"@", @encode(CGRect), "d", "d", "d"};
    sCanCloneConfig = WCKMethodMatches(cfg, NSSelectorFromString(@"bounds"), @encode(CGRect), NULL, 0)
        && WCKMethodMatches(cfg, NSSelectorFromString(@"rotationAngle"), "d", NULL, 0)
        && WCKMethodMatches(cfg, NSSelectorFromString(@"opacity"), "d", NULL, 0)
        && WCKMethodMatches(cfg, NSSelectorFromString(@"rescale"), "d", NULL, 0)
        && WCKMethodMatches(object_getClass(cfg),
            NSSelectorFromString(@"imageConfigWithTintColor:bounds:rotationAngle:opacity:scale:"),
            "@", factoryArgs, 5);
    const char *configArgs[] = {"@", "@"};
    BOOL config = sCanCloneConfig && WCKInstallHook(cls,
        NSSelectorFromString(@"imageNamed:fromConfig:"), (IMP)WCKSVGConfig,
        (IMP *)&sOriginalConfig, "@", configArgs, 2);
    WCKSetModuleStatus(@"svgTint", named && config ? @"ready" : @"部分接口不可用");
}
