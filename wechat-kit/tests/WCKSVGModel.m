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
@implementation UIImage
- (instancetype)initWithCGImage:(CGImageRef)i scale:(double)s orientation:(UIImageOrientation)o {
    if((self=[super init])){_CGImage=i;_scale=s;_imageOrientation=o;}return self;
}
- (UIImage *)clone {
    UIImage *n=[[UIImage alloc] initWithCGImage:self.CGImage scale:self.scale orientation:self.imageOrientation];
    n.capInsets=self.capInsets;n.alignmentRectInsets=self.alignmentRectInsets;n.resizingMode=self.resizingMode;
    n.renderingMode=self.renderingMode;n.wasTinted=self.wasTinted;n.paintedRGB=self.paintedRGB;return n;
}
- (UIImage *)resizableImageWithCapInsets:(UIEdgeInsets)i {return [self resizableImageWithCapInsets:i resizingMode:UIImageResizingModeTile];}
- (UIImage *)resizableImageWithCapInsets:(UIEdgeInsets)i resizingMode:(UIImageResizingMode)m {UIImage*n=[self clone];n.capInsets=i;n.resizingMode=m;return n;}
- (UIImage *)imageWithAlignmentRectInsets:(UIEdgeInsets)i {UIImage*n=[self clone];n.alignmentRectInsets=i;return n;}
- (UIImage *)imageWithRenderingMode:(UIImageRenderingMode)m {UIImage*n=[self clone];n.renderingMode=m;return n;}
- (UIImage *)imageWithTintColor:(UIColor *)c renderingMode:(UIImageRenderingMode)m {UIImage*n=[self clone];n.renderingMode=m;n.paintedRGB=c.rgb;n.wasTinted=YES;return n;}
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
+ (id)imageNamed:(id)n {originalCalls++;return source;}
+ (id)imageNamed:(id)n color:(id)c {originalCalls++;return source;}
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a {originalCalls++;return source;}
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a rotate:(double)r {originalCalls++;return source;}
+ (id)imageNamed:(id)n size:(CGSize)s {originalCalls++;return source;}
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c {originalCalls++;return source;}
+ (id)imageData:(id)d resize:(CGSize)s scale:(double)scale {originalCalls++;return source;}
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r {
    (void)s;(void)c;(void)a;(void)r;originalCalls++;return [self imageNamed:n fromConfig:@{}];
}
+ (id)imageNamed:(id)n fromConfig:(id)c {(void)c; originalCalls++;return [n isEqual:@"nil"]?nil:source;}
+ (id)imageData:(id)d fromConfig:(id)c {(void)d;(void)c;originalCalls++;return source;}
+ (id)adaptedWeSVGImageWithName:(id)n data:(id)d config:(id)c {(void)n;(void)d;(void)c;originalCalls++;return source;}
+ (id)imageWithContentsOfFile:(id)n size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r {(void)n;(void)s;(void)c;(void)a;(void)r;originalCalls++;return source;}
@end
static void set(NSString*k,id v){NSError*e=nil;CHECK([WCKSettings.shared setObject:v forKey:k error:&e]);CHECK(!e);}
int main(void){@autoreleasepool{
    NSString *home=NSProcessInfo.processInfo.environment[@"HOME"];
    CHECK([home containsString:@"wck-svg-model-"]);
    modelStore=[[WCKSettings alloc] initWithFileURL:[NSURL fileURLWithPath:
        [home stringByAppendingPathComponent:@"Library/Preferences/model.plist"]]];
    Method shared=class_getClassMethod(WCKSettings.class,@selector(shared));
    Method replacement=class_getClassMethod(WCKSettings.class,@selector(wck_modelShared));
    method_setImplementation(shared,method_getImplementation(replacement));
    source=[[UIImage alloc] initWithCGImage:(CGImageRef)0x42 scale:3 orientation:UIImageOrientationUp];
    source.capInsets=(UIEdgeInsets){1,2,3,4};source.alignmentRectInsets=(UIEdgeInsets){4,3,2,1};
    source.renderingMode=UIImageRenderingModeAlwaysTemplate;
    WCKInstallSVG();CHECK([WCKRuntimeStatuses()[@"svgTint"]isEqual:@"ready"]);
    set(@"svgTintLight",@"#112233");set(@"svgTintDark",@"#AABBCC");set(@"svgTint",@YES);
    CHECK(![WCKSettings.shared boolForKey:@"enabled"]);
    UIImage *initial=[WCSVGImage imageNamed:@"icon_a" fromConfig:@{}];
    CHECK(initial!=source);CHECK(!initial.wasTinted);CHECK(initial.scale==3);CHECK(initial.capInsets.left==2);
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
    printf("production SVG model: %d checks PASS (not UIKit rendering)\n",checks);
    return 0;
}}
