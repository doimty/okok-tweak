#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKPolicy.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static int checks;
static WCKSettings *modelStore;
@interface WCKSettings (IsolatedSVGStore)
- (instancetype)initWithFileURL:(NSURL *)url;
@end
@interface WCKSettings (SVGModelStore)
+ (instancetype)wck_modelShared;
@end
@implementation WCKSettings (SVGModelStore)
+ (instancetype)wck_modelShared { return modelStore; }
@end
#define CHECK(x) do{ ++checks; if(!(x)){fprintf(stderr,"SVG model check failed %d: %s\n",__LINE__,#x);abort();}}while(0)
@implementation UIColor
+ (instancetype)colorWithRed:(double)r green:(double)g blue:(double)b alpha:(double)a {
    (void)a; UIColor *c=[self new];c.rgb=((uint32_t)llround(r*255)<<16)|((uint32_t)llround(g*255)<<8)|(uint32_t)llround(b*255);return c;
}
@end
@implementation UITraitCollection
+ (instancetype)currentTraitCollection { UITraitCollection *c=[self new];c.userInterfaceStyle=UIUserInterfaceStyleLight;return c; }
@end
static NSString *fault;
static UIImage *faultSource;
static BOOL injected(NSString *name) { return [fault isEqual:name]; }
@implementation UIImage
- (instancetype)initWithCGImage:(CGImageRef)i scale:(double)s orientation:(UIImageOrientation)o {
    if((self=[super init])){_CGImage=i;_scale=s;_imageOrientation=o;_size=CGSizeMake(120/s,84/s);}return self;
}
- (UIImage *)clone {
    UIImage *n=[[UIImage alloc] initWithCGImage:self.CGImage scale:self.scale orientation:self.imageOrientation];
    n.size=self.size;n.images=self.images;
    n.capInsets=self.capInsets;n.alignmentRectInsets=self.alignmentRectInsets;n.resizingMode=self.resizingMode;
    n.renderingMode=self.renderingMode;n.wasTinted=self.wasTinted;n.paintedRGB=self.paintedRGB;return n;
}
- (UIImage *)resizableImageWithCapInsets:(UIEdgeInsets)i {return [self resizableImageWithCapInsets:i resizingMode:UIImageResizingModeTile];}
- (UIImage *)resizableImageWithCapInsets:(UIEdgeInsets)i resizingMode:(UIImageResizingMode)m {
    if(injected(@"resize-nil"))return nil;if(injected(@"resize-source"))return faultSource;
    if(injected(@"resize-throw"))@throw [NSException exceptionWithName:@"model" reason:nil userInfo:nil];
    UIImage*n=[self clone];n.capInsets=i;n.resizingMode=m;return n;
}
- (UIImage *)imageWithAlignmentRectInsets:(UIEdgeInsets)i {
    if(injected(@"align-nil"))return nil;if(injected(@"align-source"))return faultSource;
    UIImage*n=[self clone];n.alignmentRectInsets=i;return n;
}
- (UIImage *)imageWithRenderingMode:(UIImageRenderingMode)m {
    if(injected(@"copy-self"))return self;if(injected(@"copy-nil"))return nil;
    if(injected(@"copy-throw"))@throw [NSException exceptionWithName:@"model" reason:nil userInfo:nil];
    UIImage*n=[self clone];n.renderingMode=m;
    if(injected(@"copy-size"))n.size=CGSizeMake(40,28);
    if(injected(@"copy-scale"))n.scale=1;
    if(injected(@"copy-orientation"))n.imageOrientation=UIImageOrientationUp;
    if(injected(@"copy-cap"))n.capInsets=(UIEdgeInsets){0,0,0,0};
    if(injected(@"copy-resize"))n.resizingMode=UIImageResizingModeTile;
    if(injected(@"copy-align"))n.alignmentRectInsets=(UIEdgeInsets){0,0,0,0};
    if(injected(@"copy-render"))n.renderingMode=UIImageRenderingModeAlwaysOriginal;
    if(injected(@"copy-pixels"))n.CGImage=(CGImageRef)0xBAD;
    return n;
}
- (UIImage *)imageWithTintColor:(UIColor *)c renderingMode:(UIImageRenderingMode)m {
    if(injected(@"tint-nil"))return nil;if(injected(@"tint-source"))return faultSource;
    if(injected(@"tint-throw"))@throw [NSException exceptionWithName:@"model" reason:nil userInfo:nil];
    UIImage*n=[self clone];n.renderingMode=m;n.paintedRGB=c.rgb;n.wasTinted=YES;
    if(injected(@"tint-size"))n.size=CGSizeMake(40,28);
    if(injected(@"tint-scale"))n.scale=1;
    if(injected(@"tint-orientation"))n.imageOrientation=UIImageOrientationUp;
    if(injected(@"tint-render"))n.renderingMode=UIImageRenderingModeAlwaysOriginal;
    if(injected(@"tint-drop-metadata") || [fault hasPrefix:@"resize-"] || [fault hasPrefix:@"align-"]) {
        n.capInsets=(UIEdgeInsets){0,0,0,0};n.resizingMode=UIImageResizingModeTile;
        n.alignmentRectInsets=(UIEdgeInsets){0,0,0,0};
    }
    return n;
}
@end
@implementation UIView
- (instancetype)init { if((self=[super init]))_traitCollection=[UITraitCollection currentTraitCollection];return self; }
- (void)traitCollectionDidChange:(UITraitCollection *)old {(void)old;}
@end
@implementation UIImageView
@end
@interface UIButton ()
@property(strong) NSMutableDictionary *imagesByState;
@end
@implementation UIButton
- (void)setImage:(UIImage *)i forState:(UIControlState)s { if(!self.imagesByState)self.imagesByState=[NSMutableDictionary dictionary]; if(i)self.imagesByState[@(s)]=i;else [self.imagesByState removeObjectForKey:@(s)]; }
- (UIImage *)imageForState:(UIControlState)s {return self.imagesByState[@(s)];}
@end
static NSMutableDictionary *statuses;
BOOL WCKHostIsSupported(void){return YES;}
NSDictionary *WCKRuntimeStatuses(void){return [statuses copy]?:@{};}
void WCKSetModuleStatus(NSString *k,NSString*v){if(!statuses)statuses=[NSMutableDictionary dictionary];statuses[k]=v;}
BOOL WCKEnabled(NSString*k){NSDictionary*s=WCKSettings.shared.snapshot;return [statuses[k] isEqual:@"ready"]&&[s[@"enabled"]boolValue]&&[s[k]boolValue];}
BOOL WCKMethodMatches(Class cls,SEL sel,const char*r,const char*const*args,unsigned int n){
    Method m=class_getInstanceMethod(cls,sel);if(!m||method_getNumberOfArguments(m)!=n+2)return NO;
    char *v=method_copyReturnType(m);BOOL ok=WCKTypeMatches(v,r);free(v);
    for(NSUInteger i=0;ok&&i<n;i++){v=method_copyArgumentType(m,(unsigned)i+2);ok=WCKTypeMatches(v,args[i]);free(v);}return ok;
}
BOOL WCKInstallHook(Class c,SEL s,IMP imp,IMP*orig,const char*r,const char*const*a,unsigned int n){
    if(!WCKMethodMatches(c,s,r,a,n))return NO;
    Method m=class_getInstanceMethod(c,s);*orig=method_getImplementation(m);
    // Add an inherited method to this class first, to preserve the superclass chain.
    if(!class_addMethod(c,s,imp,method_getTypeEncoding(m)))method_setImplementation(m,imp);
    return YES;
}
// Representative original factories: never write the argument config or shared source.
static UIImage *source;
static NSUInteger originalCalls;
static NSString *lastFactory;
static id lastName,lastColor,lastConfig,lastData;
static CGSize lastSize;
static double lastScale,lastAlpha,lastRotate;
static UIImage *sizedSource(CGSize size, double scale) {
    UIImage *image=[source clone];image.size=size;if(scale>0)image.scale=scale;return image;
}
@interface WCSVGImage : NSObject
+ (id)imageNamed:(id)n;
+ (id)imageNamed:(id)n color:(id)c;
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a;
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a rotate:(double)r;
+ (id)imageNamed:(id)n size:(CGSize)s;
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c;
+ (id)imageData:(id)d resize:(CGSize)s scale:(double)scale;
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r;
+ (id)imageNamed:(id)n fromConfig:(id)c;
+ (id)imageData:(id)d fromConfig:(id)c;
+ (id)adaptedWeSVGImageWithName:(id)n data:(id)d config:(id)c;
+ (id)imageWithContentsOfFile:(id)n size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r;
@end
@implementation WCSVGImage
+ (id)imageNamed:(id)n {originalCalls++;lastFactory=@"simple";lastName=n;return source;}
+ (id)imageNamed:(id)n color:(id)c {originalCalls++;lastFactory=@"color";lastName=n;lastColor=c;return source;}
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a {originalCalls++;lastFactory=@"alpha";lastName=n;lastColor=c;lastAlpha=a;return source;}
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a rotate:(double)r {originalCalls++;lastFactory=@"rotate";lastName=n;lastColor=c;lastAlpha=a;lastRotate=r;return source;}
+ (id)imageNamed:(id)n size:(CGSize)s {originalCalls++;lastFactory=@"size";lastName=n;lastSize=s;return sizedSource(s,0);}
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c {originalCalls++;lastFactory=@"sizeColor";lastName=n;lastSize=s;lastColor=c;return sizedSource(s,0);}
+ (id)imageData:(id)d resize:(CGSize)s scale:(double)scale {originalCalls++;lastFactory=@"resizeData";lastData=d;lastSize=s;lastScale=scale;return sizedSource(s,scale);}
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r {
    originalCalls++;id nested=[self imageNamed:n fromConfig:@{}];CHECK(nested==source);
    lastFactory=@"named";lastName=n;lastSize=s;lastColor=c;lastAlpha=a;lastRotate=r;return sizedSource(s,0);
}
+ (id)imageNamed:(id)n fromConfig:(id)c {
    originalCalls++;lastFactory=@"config";lastName=n;lastConfig=c;
    if([n isEqual:@"throw"])@throw [NSException exceptionWithName:@"factory" reason:nil userInfo:nil];
    return [n isEqual:@"nil"]?nil:source;
}
+ (id)imageData:(id)d fromConfig:(id)c {originalCalls++;lastFactory=@"data";lastData=d;lastConfig=c;return source;}
+ (id)adaptedWeSVGImageWithName:(id)n data:(id)d config:(id)c {originalCalls++;lastFactory=@"adapted";lastName=n;lastData=d;lastConfig=c;return source;}
+ (id)imageWithContentsOfFile:(id)n size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r {
    originalCalls++;lastFactory=@"file";lastName=n;lastSize=s;lastColor=c;lastAlpha=a;lastRotate=r;return sizedSource(s,0);
}
@end
static void set(NSString*k,id v){NSError*e=nil;CHECK([WCKSettings.shared setObject:v forKey:k error:&e]);CHECK(!e);}
static void metadata(UIImage *image, UIImage *expected) {
    CHECK(image!=nil);CHECK(image.size.width==expected.size.width);CHECK(image.size.height==expected.size.height);
    CHECK(image.scale==expected.scale);CHECK(image.imageOrientation==expected.imageOrientation);
    CHECK(UIEdgeInsetsEqualToEdgeInsets(image.capInsets,expected.capInsets));
    CHECK(image.resizingMode==expected.resizingMode);
    CHECK(UIEdgeInsetsEqualToEdgeInsets(image.alignmentRectInsets,expected.alignmentRectInsets));
    CHECK(image.renderingMode==expected.renderingMode);
}
static void immutable(UIImage *image, UIImage *saved) {
    metadata(image,saved);CHECK(image.CGImage==saved.CGImage);CHECK(image.images==saved.images);
    CHECK(image.wasTinted==saved.wasTinted);CHECK(image.paintedRGB==saved.paintedRGB);
}
static void factoryContracts(void) {
    NSString *name=@"contract";id color=[UIColor new];NSData *data=[NSData data];
    NSMutableDictionary *config=[@{@"immutable":@YES} mutableCopy];NSDictionary *saved=[config copy];
    CGSize size=CGSizeMake(9.25,17.5);UIImage *expected=sizedSource(size,0),*image;
#define FACTORY(kind,call,expectedImage) do { image=(call);CHECK([lastFactory isEqual:(kind)]);metadata(image,(expectedImage));CHECK(image.wasTinted); } while(0)
    FACTORY(@"simple",[WCSVGImage imageNamed:name],source);CHECK(lastName==name);
    FACTORY(@"color",[WCSVGImage imageNamed:name color:color],source);CHECK(lastName==name&&lastColor==color);
    FACTORY(@"alpha",[WCSVGImage imageNamed:name color:color alpha:0.375],source);CHECK(lastName==name&&lastColor==color&&lastAlpha==0.375);
    FACTORY(@"rotate",[WCSVGImage imageNamed:name color:color alpha:0.375 rotate:1.25],source);CHECK(lastName==name&&lastColor==color&&lastAlpha==0.375&&lastRotate==1.25);
    FACTORY(@"size",[WCSVGImage imageNamed:name size:size],expected);CHECK(lastName==name&&CGSizeEqualToSize(lastSize,size));
    FACTORY(@"sizeColor",[WCSVGImage imageNamed:name size:size color:color],expected);CHECK(lastName==name&&lastColor==color&&CGSizeEqualToSize(lastSize,size));
    UIImage *scaled=sizedSource(size,2);
    FACTORY(@"resizeData",[WCSVGImage imageData:data resize:size scale:2],scaled);CHECK(lastData==data&&lastScale==2&&CGSizeEqualToSize(lastSize,size));
    FACTORY(@"named",[WCSVGImage imageNamed:name size:size color:color alpha:0.375 rotate:1.25],expected);
    CHECK(lastName==name&&lastColor==color&&lastAlpha==0.375&&lastRotate==1.25&&CGSizeEqualToSize(lastSize,size));
    FACTORY(@"file",[WCSVGImage imageWithContentsOfFile:name size:size color:color alpha:0.375 rotate:1.25],expected);
    CHECK(lastName==name&&lastColor==color&&lastAlpha==0.375&&lastRotate==1.25&&CGSizeEqualToSize(lastSize,size));
    FACTORY(@"config",[WCSVGImage imageNamed:name fromConfig:config],source);CHECK(lastName==name&&lastConfig==config);
    FACTORY(@"data",[WCSVGImage imageData:data fromConfig:config],source);CHECK(lastData==data&&lastConfig==config);
    FACTORY(@"adapted",[WCSVGImage adaptedWeSVGImageWithName:name data:data config:config],source);CHECK(lastName==name&&lastData==data&&lastConfig==config);
    CHECK([config isEqual:saved]);
#undef FACTORY
}
static void geometryAndFailures(void);
int main(void){@autoreleasepool{
    NSString *home=NSProcessInfo.processInfo.environment[@"HOME"];
    CHECK([home containsString:@"wck-svg-model-"]);
    modelStore=[[WCKSettings alloc] initWithFileURL:[NSURL fileURLWithPath:
        [home stringByAppendingPathComponent:@"Library/Preferences/model.plist"]]];
    Method shared=class_getClassMethod(WCKSettings.class,@selector(shared));
    Method replacement=class_getClassMethod(WCKSettings.class,@selector(wck_modelShared));
    method_setImplementation(shared,method_getImplementation(replacement));
    source=[[UIImage alloc] initWithCGImage:(CGImageRef)0x42 scale:3 orientation:UIImageOrientationRight];
    // Logical dimensions intentionally differ from backing pixels / scale.
    source.size=CGSizeMake(13.5,7.25);source.resizingMode=UIImageResizingModeStretch;
    source.capInsets=(UIEdgeInsets){1,2,3,4};source.alignmentRectInsets=(UIEdgeInsets){4,3,2,1};
    source.renderingMode=UIImageRenderingModeAlwaysTemplate;
    UIImage *savedSource=[source clone];
    WCKInstallSVG();CHECK([WCKRuntimeStatuses()[@"svgTint"]isEqual:@"ready"]);
    set(@"svgTintLight",@"#112233");set(@"svgTintDark",@"#AABBCC");set(@"svgTint",@YES);
    CHECK(![WCKSettings.shared boolForKey:@"enabled"]);
    UIImage *initial=[WCSVGImage imageNamed:@"icon_a" fromConfig:@{}];
    CHECK(initial!=source);CHECK(!initial.wasTinted);CHECK(initial.scale==3);CHECK(initial.capInsets.left==2);
    metadata(initial,savedSource);CHECK(initial.CGImage==source.CGImage);immutable(source,savedSource);
    UIImageView *iv=[UIImageView new];iv.image=initial;CHECK(!iv.image.wasTinted);
    set(@"enabled",@YES);CHECK(iv.image.wasTinted&&iv.image.paintedRGB==0x112233);CHECK(!source.wasTinted);
    iv.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;[iv traitCollectionDidChange:nil];
    CHECK(iv.image.paintedRGB==0xAABBCC);
    set(@"svgTint",@NO);CHECK(!iv.image.wasTinted);
    // This re-assignment caught a real provenance loss in the first draft.
    iv.image=iv.image;set(@"svgTint",@YES);CHECK(iv.image.paintedRGB==0xAABBCC);
    UIImage *photo=[[UIImage alloc] initWithCGImage:(CGImageRef)0x99 scale:2 orientation:0];
    iv.image=photo;set(@"svgTintDark",@"#334455");CHECK(iv.image==photo);CHECK(!photo.wasTinted);
    iv.image=[WCSVGImage imageNamed:@"icon_a" fromConfig:@{}];
    set(@"svgExclude",@"icon_a");CHECK(!iv.image.wasTinted);set(@"svgExclude",@"");CHECK(iv.image.paintedRGB==0x334455);
    set(@"svgInclude",@"icon_b");CHECK(!iv.image.wasTinted);set(@"svgInclude",@"");CHECK(iv.image.wasTinted);
    NSMutableDictionary *config=[@{@"tint":@"unchanged"} mutableCopy];NSDictionary *saved=[config copy];
    NSUInteger before=originalCalls;
    UIImage *nested=[WCSVGImage imageNamed:@"icon_n" size:(CGSize){8,8} color:nil alpha:0.5 rotate:1];
    CHECK(originalCalls==before+2);CHECK(nested!=source&&nested.wasTinted);CHECK(!source.wasTinted);
    CHECK([WCSVGImage imageNamed:@"nil" fromConfig:config]==nil);CHECK([config isEqual:saved]);
    UIButton *b=[UIButton new];[b setImage:initial forState:0];[b setImage:initial forState:1];
    CHECK([b imageForState:0].paintedRGB==0x112233);
    set(@"svgTintLight",@"#556677");CHECK([b imageForState:0].paintedRGB==0x556677);
    CHECK([b imageForState:1].paintedRGB==0x556677);
    iv.highlightedImage=initial;CHECK(iv.highlightedImage.paintedRGB==0x334455);
    set(@"enabled",@NO);CHECK(![b imageForState:0].wasTinted&&!iv.highlightedImage.wasTinted);
    CHECK(!source.wasTinted&&source.renderingMode==UIImageRenderingModeAlwaysTemplate);
    // Short overloads intentionally DO NOT forward: each production hook must work.
    set(@"enabled",@YES);
    NSArray *factoryImages=@[[WCSVGImage imageNamed:@"short"],
        [WCSVGImage imageNamed:@"short" color:nil],
        [WCSVGImage imageNamed:@"short" color:nil alpha:0.3],
        [WCSVGImage imageNamed:@"short" color:nil alpha:0.3 rotate:0.1],
        [WCSVGImage imageNamed:@"short" size:(CGSize){5,6}],
        [WCSVGImage imageNamed:@"short" size:(CGSize){5,6} color:nil],
        [WCSVGImage imageData:[NSData data] resize:(CGSize){5,6} scale:2]];
    for(UIImage *img in factoryImages) CHECK(img.wasTinted&&img!=source);
    UIImage *originalSVG=[WCSVGImage imageNamed:@"transformed"];
    UIImage *mode=[originalSVG imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *stretch=[mode resizableImageWithCapInsets:(UIEdgeInsets){9,8,7,6} resizingMode:UIImageResizingModeStretch];
    UIImage *aligned=[stretch imageWithAlignmentRectInsets:(UIEdgeInsets){6,7,8,9}];
    UIImage *shortResize=[originalSVG resizableImageWithCapInsets:(UIEdgeInsets){3,4,5,6}];
    UIImageView *changed=[UIImageView new];changed.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;
    changed.image=aligned;CHECK(changed.image.paintedRGB==0x334455);CHECK(changed.image.capInsets.left==8);CHECK(changed.image.alignmentRectInsets.right==9);
    set(@"svgTintDark",@"#ABCDEF");CHECK(changed.image.paintedRGB==0xABCDEF);
    set(@"enabled",@NO);CHECK(!changed.image.wasTinted);CHECK(changed.image.capInsets.left==8);CHECK(changed.image.alignmentRectInsets.right==9);
    changed.image=shortResize;CHECK(!changed.image.wasTinted);CHECK(changed.image.capInsets.left==4);
    UIImage *photoCopy=[photo imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    changed.image=photoCopy;set(@"enabled",@YES);CHECK(changed.image==photoCopy);CHECK(!photoCopy.wasTinted);
    CHECK(!source.wasTinted&&source.capInsets.left==2);
    factoryContracts();geometryAndFailures();immutable(source,savedSource);
    printf("production SVG model: %d checks PASS (not UIKit rendering)\n",checks);
    return 0;
}}

static void geometryAndFailures(void) {
    UIImage *saved=[source clone];faultSource=source;
    for(NSNumber *enabled in @[@NO,@YES]) {
        set(@"enabled",enabled);
        for(NSNumber *mode in @[@(UIImageRenderingModeAutomatic),@(UIImageRenderingModeAlwaysOriginal),@(UIImageRenderingModeAlwaysTemplate)]) {
            UIImage *base=[WCSVGImage imageNamed:@"transforms"];
            UIImage *expected=[source clone];expected.renderingMode=mode.integerValue;
            UIImage *changed=[base imageWithRenderingMode:mode.integerValue];metadata(changed,expected);
            CHECK(changed.wasTinted==enabled.boolValue);
            UIEdgeInsets caps={1.25,2.5,3.75,4.5},align={-4,3,-2,1};
            changed=[changed resizableImageWithCapInsets:caps];expected.capInsets=caps;expected.resizingMode=UIImageResizingModeTile;
            metadata(changed,expected);
            for(NSNumber *resize in @[@(UIImageResizingModeTile),@(UIImageResizingModeStretch)]) {
                changed=[changed resizableImageWithCapInsets:caps resizingMode:resize.integerValue];expected.resizingMode=resize.integerValue;
                metadata(changed,expected);
                changed=[changed imageWithAlignmentRectInsets:align];expected.alignmentRectInsets=align;metadata(changed,expected);
                UIImageView *view=[UIImageView new];view.image=changed;metadata(view.image,expected);
                view.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;[view traitCollectionDidChange:nil];metadata(view.image,expected);
                view.image=view.image;metadata(view.image,expected);
                immutable(source,saved);
            }
        }
        for(NSString *bad in @[@"copy-size",@"copy-scale",@"copy-orientation",@"copy-cap",@"copy-resize",@"copy-align",@"copy-render",@"copy-pixels",@"copy-self",@"copy-nil",@"copy-throw"]) {
            fault=bad;UIImage *result=[WCSVGImage imageNamed:@"fail-closed"];fault=nil;
            CHECK(result==source);immutable(source,saved);
        }
    }
    set(@"enabled",@YES);
    for(NSString *bad in @[@"tint-nil",@"tint-source",@"tint-throw",@"tint-size",@"tint-scale",@"tint-orientation",@"tint-render",@"resize-nil",@"resize-source",@"resize-throw",@"align-nil",@"align-source"]) {
        fault=bad;UIImage *result=[WCSVGImage imageNamed:@"atomic-failure"];fault=nil;
        CHECK(result==source);immutable(source,saved);
        UIImage *recovered=[WCSVGImage imageNamed:@"recovered"];CHECK(recovered.wasTinted);metadata(recovered,source);
    }
    fault=@"tint-drop-metadata";UIImage *restored=[WCSVGImage imageNamed:@"restored"];fault=nil;
    CHECK(restored.wasTinted);metadata(restored,source);
    BOOL threw=NO;
    @try { (void)[WCSVGImage imageNamed:@"throw" fromConfig:@{}]; }
    @catch(NSException *e) { CHECK([e.name isEqual:@"factory"]);threw=YES; }CHECK(threw);
    UIImage *tagged=[WCSVGImage imageNamed:@"after-factory-throw"];CHECK(tagged.wasTinted);
    threw=NO;fault=@"resize-throw";
    @try { (void)[tagged resizableImageWithCapInsets:(UIEdgeInsets){7,6,5,4} resizingMode:UIImageResizingModeTile]; }
    @catch(NSException *e) { CHECK([e.name isEqual:@"model"]);threw=YES; }fault=nil;CHECK(threw);
    CHECK([tagged imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate].wasTinted);
    // A raw cache source remains untagged even after all factory/transform paths.
    UIImageView *raw=[UIImageView new];raw.image=source;set(@"svgTintLight",@"#765432");CHECK(raw.image==source);
    UIImage *untagged=[source imageWithAlignmentRectInsets:(UIEdgeInsets){8,7,6,5}];CHECK(!untagged.wasTinted);
    raw.image=untagged;set(@"svgTintLight",@"#112233");CHECK(raw.image==untagged);
    for(NSNumber *scale in @[@1,@2,@3]) {
        UIImage *original=source;source=[original clone];source.scale=scale.doubleValue;source.size=CGSizeMake(11.25,5.5);
        for(NSNumber *orientation in @[@(UIImageOrientationUp),@(UIImageOrientationRight),@(UIImageOrientationLeftMirrored)]) {
            source.imageOrientation=orientation.integerValue;UIImage *result=[WCSVGImage imageNamed:@"geometry"];metadata(result,source);CHECK(result.wasTinted);
        }
        source=original;
    }
    UIImage *original=source;source=[original clone];source.images=@[original];
    CHECK([WCSVGImage imageNamed:@"animated"]==source);source=[original clone];source.CGImage=NULL;
    CHECK([WCSVGImage imageNamed:@"no-bitmap"]==source);source=original;
    immutable(source,saved);
}
