// Links actual WCKSVG.m. Foundation models verify contracts, not UIKit pixels.
#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKPolicy.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
static unsigned checks,forbiddenImageOps,transforms,traitReads,setterAssignments;
static void (^duringFactory)(void);
static BOOL modeDependsOnColor;
static __weak id latestSVGDriver;
static IMP originalDriverNormalSetter;
static void trackedDriverNormalSetter(id receiver,SEL cmd,id slot){
 latestSVGDriver=receiver;((void(*)(id,SEL,id))originalDriverNormalSetter)(receiver,cmd,slot);
}
#define CHECK(x) do { ++checks;if(!(x)){fprintf(stderr,"SVG PARAM CHECK failed %d: %s\n",__LINE__,#x);abort();} } while(0)
static WCKSettings *store;
@interface WCKSettings (ParameterStore)
- (instancetype)initWithFileURL:(NSURL*)url;
@end
@interface WCKSettings (ParameterFixture)
+ (instancetype)parameterShared;
@end
@implementation WCKSettings (ParameterFixture)
+ (instancetype)parameterShared{return store;}
@end
@implementation UIColor
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a{
 CHECK(a==1);UIColor*c=[self new];c.rgb=((uint32_t)llround(r*255)<<16)|((uint32_t)llround(g*255)<<8)|(uint32_t)llround(b*255);return c;
}
@end
@implementation UITraitCollection
+ (instancetype)currentTraitCollection{CHECK(NSThread.isMainThread);++traitReads;UITraitCollection*t=[self new];t.userInterfaceStyle=UIUserInterfaceStyleLight;return t;}
@end
@implementation UIImage
- (instancetype)init{if((self=[super init])){_scale=3;_size=CGSizeMake(23,19);_operations=@[];_imageOrientation=UIImageOrientationLeftMirrored;_capInsets=(UIEdgeInsets){1,2,3,4};_alignmentRectInsets=(UIEdgeInsets){4,3,2,1};_resizingMode=UIImageResizingModeStretch;}return self;}
- (UIImage*)fixtureClone{UIImage*n=[UIImage new];n.size=self.size;n.scale=self.scale;n.imageOrientation=self.imageOrientation;n.capInsets=self.capInsets;n.alignmentRectInsets=self.alignmentRectInsets;n.resizingMode=self.resizingMode;n.renderingMode=self.renderingMode;n.images=self.images;n.duration=self.duration;n.paintedRGB=self.paintedRGB;n.operations=self.operations;n.returnSelf=self.returnSelf;return n;}
// The production implementation must never inspect or flatten the backing buffer.
- (CGImageRef)CGImage{++forbiddenImageOps;return (CGImageRef)0x42;}
- (instancetype)initWithCGImage:(CGImageRef)i scale:(CGFloat)s orientation:(UIImageOrientation)o{++forbiddenImageOps;if((self=[self init])){self.size=CGSizeMake(120/s,84/s);self.scale=s;self.imageOrientation=o;}return self;}
- (UIImage*)imageWithTintColor:(UIColor*)c renderingMode:(UIImageRenderingMode)m{++forbiddenImageOps;UIImage*n=[self fixtureClone];n.paintedRGB=c.rgb;n.renderingMode=m;return n;}
- (UIImage*)appendOperation:(NSString*)op{++transforms;if(self.returnSelf)return self;UIImage*n=[self fixtureClone];n.operations=[self.operations arrayByAddingObject:op];return n;}
- (UIImage*)imageWithRenderingMode:(UIImageRenderingMode)m{if(modeDependsOnColor&&self.renderingMode==m){++transforms;return self;}UIImage*n=[self appendOperation:[NSString stringWithFormat:@"mode:%ld",(long)m]];if(n!=self)n.renderingMode=m;return n;}
- (UIImage*)resizableImageWithCapInsets:(UIEdgeInsets)i{UIImage*n=[self appendOperation:@"insets"];if(n!=self){n.capInsets=i;n.resizingMode=UIImageResizingModeTile;}return n;}
- (UIImage*)resizableImageWithCapInsets:(UIEdgeInsets)i resizingMode:(UIImageResizingMode)m{UIImage*n=[self appendOperation:[NSString stringWithFormat:@"resize:%ld",(long)m]];if(n!=self){n.capInsets=i;n.resizingMode=m;}return n;}
- (UIImage*)imageWithAlignmentRectInsets:(UIEdgeInsets)i{UIImage*n=[self appendOperation:@"align"];if(n!=self)n.alignmentRectInsets=i;return n;}
@end
@implementation UIView
- (instancetype)init{if((self=[super init]))_traitCollection=[UITraitCollection currentTraitCollection];return self;}
- (void)traitCollectionDidChange:(UITraitCollection*)p{}
@end
@implementation UIImageView
@synthesize image=_image;
- (void)setImage:(UIImage*)image{++setterAssignments;_image=image;}
- (UIImage*)image{return _image;}
- (void)replaceOutsideHook:(UIImage*)image{_image=image;}
@end
@interface UIButton ()
@property(strong) NSMutableDictionary *stateImages;
@end
@implementation UIButton
- (void)setImage:(UIImage*)i forState:(UIControlState)s{if(!self.stateImages)self.stateImages=[NSMutableDictionary new];if(i)self.stateImages[@(s)]=i;else [self.stateImages removeObjectForKey:@(s)];}
- (UIImage*)imageForState:(UIControlState)s{return self.stateImages[@(s)];}
@end
static NSMutableDictionary *statuses;
BOOL WCKHostIsSupported(void){return YES;}
NSDictionary *WCKRuntimeStatuses(void){return statuses.copy;}
void WCKSetModuleStatus(NSString*k,NSString*v){statuses[k]=v;}
BOOL WCKEnabled(NSString*k){NSDictionary*s=store.snapshot;return [statuses[k]isEqual:@"ready"]&&[s[@"enabled"]boolValue]&&[s[k]boolValue];}
BOOL WCKMethodMatches(Class c,SEL s,const char*r,const char*const*a,unsigned n){
 Method m=c?class_getInstanceMethod(c,s):NULL;if(!m||method_getNumberOfArguments(m)!=n+2)return NO;
 char*t=method_copyReturnType(m);BOOL ok=WCKTypeMatches(t,r);free(t);
 for(unsigned i=0;ok&&i<n;i++){t=method_copyArgumentType(m,i+2);ok=WCKTypeMatches(t,a[i]);free(t);}return ok;
}
BOOL WCKInstallHook(Class c,SEL s,IMP imp,IMP*old,const char*r,const char*const*a,unsigned n){
 if(!WCKMethodMatches(c,s,r,a,n))return NO;Method m=class_getInstanceMethod(c,s);*old=method_getImplementation(m);
 if(!class_addMethod(c,s,imp,method_getTypeEncoding(m)))method_setImplementation(m,imp);return YES;
}
static void setting(NSString*k,id v){NSError*e=nil;CHECK([store setObject:v forKey:k error:&e]);CHECK(!e);}
static BOOL subclassFactory;
static unsigned subclassTransformCalls,subclassSetterCalls;
@interface SVGSubclass:UIImage @end
@implementation SVGSubclass
- (UIImage*)imageWithAlignmentRectInsets:(UIEdgeInsets)i{++subclassTransformCalls;return [super imageWithAlignmentRectInsets:i];}
@end
@interface SVGCarrier:UIImageView @end
@implementation SVGCarrier
- (void)setImage:(UIImage*)image{++subclassSetterCalls;[super setImage:image];}
@end
static UIColor *originalColor;
static NSMutableArray *calls;
static NSMutableDictionary *cache;
static BOOL cacheOn,throwFactory,returnNil,nonImage,animated,selfTransforms,aliasOutput;
static UIImage *lastReturned,*aliasImage;
static id produce(NSString*kind,id input,CGSize size,CGFloat scale,double angle,double alpha,id color){
 void (^callback)(void)=duringFactory;duringFactory=nil;if(callback)callback();
 [calls addObject:@{@"kind":kind,@"input":input?:NSNull.null,@"w":@(size.width),@"h":@(size.height),@"scale":@(scale),@"angle":@(angle),@"alpha":@(alpha),@"color":color?:NSNull.null}];
 if(throwFactory)@throw [NSException exceptionWithName:@"HostFactory" reason:nil userInfo:nil];
 if(returnNil && color!=originalColor)return nil;
 if(nonImage)return @"host non-image result";
 uint32_t rgb=[color isKindOfClass:UIColor.class]?[(UIColor*)color rgb]:0;
 NSString*key=[NSString stringWithFormat:@"%@/%@/%g/%g/%g/%g/%g/%u",kind,input,size.width,size.height,scale,angle,alpha,rgb];
 UIImage*i=cacheOn?cache[key]:nil;
 if(aliasOutput)i=aliasImage?:[UIImage new];
 if(!i){i=subclassFactory?[SVGSubclass new]:[UIImage new];i.size=size;i.scale=scale;i.paintedRGB=rgb;i.returnSelf=selfTransforms;if(animated){i.images=@[[UIImage new],[UIImage new]];i.duration=0.8;}if(cacheOn)cache[key]=i;}
 if(modeDependsOnColor)i.renderingMode=color==originalColor?UIImageRenderingModeAutomatic:UIImageRenderingModeAlwaysTemplate;
 if(aliasOutput)aliasImage=i;lastReturned=i;return i;
}
@interface WeSVGVM:NSObject
+ (id)imageWithName:(id)n size:(CGSize)s scale:(double)k rotation:(double)r opacity:(double)a color:(id)c;
@end
@implementation WeSVGVM
+ (id)imageWithName:(id)n size:(CGSize)s scale:(double)k rotation:(double)r opacity:(double)a color:(id)c{return produce(@"VM",n,s,k,r,a,c);}
@end
@interface WeSVGEngine:NSObject
+ (id)imageWithData:(id)d size:(CGSize)s scale:(double)k rotation:(double)r opacity:(double)a color:(id)c;
@end
@implementation WeSVGEngine
+ (id)imageWithData:(id)d size:(CGSize)s scale:(double)k rotation:(double)r opacity:(double)a color:(id)c{return produce(@"Engine",d,s,k,r,a,c);}
@end
static NSUInteger themeCalls;
static id lastThemeName,lastThemeColor;
static int lastThemeAngle;
static BOOL lastThemeIgnore;
static CGSize lastThemeSize;
static double lastThemeAlpha;
@interface MMThemeManager:NSObject
- (id)svgImageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a angle:(int)r ignoreNotFound:(BOOL)b;
@end
@implementation MMThemeManager
- (id)svgImageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a angle:(int)r ignoreNotFound:(BOOL)b{
 ++themeCalls;lastThemeName=n;lastThemeColor=c;lastThemeSize=s;lastThemeAlpha=a;lastThemeAngle=r;lastThemeIgnore=b;
 // Representative nested path, with the exact two different angle ABIs.
 return [WeSVGVM imageWithName:n size:s scale:3 rotation:r*M_PI/180.0 opacity:a color:c];
}
@end
// Host-routing fixture backed by IMP windows in host-svg-short-routing-main.txt.
// It does NOT model other plugins replacing these methods without forwarding.
@interface SVGFixtureConfig:NSObject
@property CGSize bounds;
@property double scale,rotation,alpha;
@property(strong) id color;
@end
@implementation SVGFixtureConfig @end
@interface WCSVGImage:NSObject
+ (id)imageNamed:(id)n;
+ (id)imageNamed:(id)n color:(id)c;
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a;
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a rotate:(double)r;
+ (id)imageNamed:(id)n size:(CGSize)s;
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c;
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r;
+ (id)imageWithContentsOfFile:(id)f size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r;
+ (id)imageNamed:(id)n fromConfig:(id)c;
+ (id)imageData:(id)d fromConfig:(id)c;
+ (id)adaptedWeSVGImageWithName:(id)n data:(id)d config:(id)c;
+ (id)imageData:(id)d resize:(CGSize)s scale:(double)k;
@end
static SVGFixtureConfig* config(CGSize s,id c,double a,double r,double k){SVGFixtureConfig*x=[SVGFixtureConfig new];x.bounds=s;x.color=c;x.alpha=a;x.rotation=r;x.scale=k;return x;}
@implementation WCSVGImage
+ (id)imageNamed:(id)n{return [self imageNamed:n size:CGSizeMake(23,19) color:originalColor alpha:1 rotate:0];}
+ (id)imageNamed:(id)n color:(id)c{return [self imageNamed:n size:CGSizeMake(23,19) color:c alpha:1 rotate:0];}
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a{return [self imageNamed:n size:CGSizeMake(23,19) color:c alpha:a rotate:0];}
+ (id)imageNamed:(id)n color:(id)c alpha:(double)a rotate:(double)r{return [self imageNamed:n size:CGSizeMake(23,19) color:c alpha:a rotate:r];}
+ (id)imageNamed:(id)n size:(CGSize)s{return [self imageNamed:n size:s color:originalColor alpha:1 rotate:0];}
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c{return [self imageNamed:n size:s color:c alpha:1 rotate:0];}
+ (id)imageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r{return [self imageNamed:n fromConfig:config(s,c,a,r,3)];}
+ (id)imageNamed:(id)n fromConfig:(id)c{
 // Real host falls back to NSData by passing nil name, not the original name.
 if([n isEqual:@"engine_named"])return [self adaptedWeSVGImageWithName:nil data:[@"named-svg" dataUsingEncoding:NSUTF8StringEncoding] config:c];
 return [self adaptedWeSVGImageWithName:n data:nil config:c];
}
+ (id)imageWithContentsOfFile:(id)f size:(CGSize)s color:(id)c alpha:(double)a rotate:(double)r{return [self imageData:[@"file-svg" dataUsingEncoding:NSUTF8StringEncoding] fromConfig:config(s,c,a,r,3)];}
+ (id)imageData:(id)d fromConfig:(id)c{return [self adaptedWeSVGImageWithName:nil data:d config:c];}
+ (id)adaptedWeSVGImageWithName:(id)n data:(id)d config:(SVGFixtureConfig*)c{
 return [n length]?[WeSVGVM imageWithName:n size:c.bounds scale:c.scale rotation:c.rotation opacity:c.alpha color:c.color]:[WeSVGEngine imageWithData:d size:c.bounds scale:c.scale rotation:c.rotation opacity:c.alpha color:c.color];
}
+ (id)imageData:(id)d resize:(CGSize)s scale:(double)k{return [self imageData:d fromConfig:config(s,originalColor,1,0,k)];}
@end
static void metadata(UIImage*i,CGSize size,double scale){
 CHECK(i);CHECK(CGSizeEqualToSize(i.size,size));CHECK(i.scale==scale);CHECK(i.imageOrientation==UIImageOrientationLeftMirrored);
 CHECK(UIEdgeInsetsEqualToEdgeInsets(i.capInsets,((UIEdgeInsets){1,2,3,4})));
 CHECK(UIEdgeInsetsEqualToEdgeInsets(i.alignmentRectInsets,((UIEdgeInsets){4,3,2,1})));
 CHECK(i.resizingMode==UIImageResizingModeStretch);CHECK(i.renderingMode==UIImageRenderingModeAutomatic);
}
static UIImage* vm(NSString*n){return [WeSVGVM imageWithName:n size:CGSizeMake(23,19) scale:3 rotation:0.34 opacity:0.73 color:originalColor];}
static void initFixture(void){
 NSString*home=NSProcessInfo.processInfo.environment[@"HOME"];CHECK([home containsString:@"wck-svg-param-"]);
 store=[[WCKSettings alloc]initWithFileURL:[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"settings/test.plist"]]];
 Method a=class_getClassMethod(WCKSettings.class,@selector(shared)),b=class_getClassMethod(WCKSettings.class,@selector(parameterShared));method_setImplementation(a,method_getImplementation(b));
 statuses=[NSMutableDictionary new];calls=[NSMutableArray new];cache=[NSMutableDictionary new];originalColor=[UIColor new];originalColor.rgb=0x223344;
 const char*driverArgs[]={"@"};CHECK(WCKInstallHook(NSClassFromString(@"WCKSVGDriver"),NSSelectorFromString(@"setNormal:"),(IMP)trackedDriverNormalSetter,&originalDriverNormalSetter,"v",driverArgs,1));
 WCKInstallSVG();CHECK([statuses[@"svgTint"]isEqual:@"ready"]);
 setting(@"svgTintLight",@"#112233");setting(@"svgTintDark",@"#AABBCC");setting(@"enabled",@YES);setting(@"svgTint",@YES);
}
static void parameters(void){
 CGSize sz={31,17};MMThemeManager*t=[MMThemeManager new];
 NSUInteger count=calls.count;UIImage*i=[t svgImageNamed:@"chat_icon" size:sz color:originalColor alpha:0.42 angle:-17 ignoreNotFound:YES];
 CHECK(themeCalls==1&&calls.count==count+1);CHECK(i==lastReturned);CHECK([lastThemeName isEqual:@"chat_icon"]);
 CHECK(lastThemeSize.width==31&&lastThemeSize.height==17&&lastThemeAlpha==0.42&&lastThemeAngle==-17&&lastThemeIgnore);
 CHECK([lastThemeColor rgb]==0x112233);metadata(i,sz,3);CHECK(i.paintedRGB==0x112233);CHECK(transforms==0);
 NSDictionary*c=calls.lastObject;CHECK([c[@"angle"]doubleValue]==-17*M_PI/180.0&&[c[@"alpha"]doubleValue]==0.42);
 NSData*data=[@"svg" dataUsingEncoding:NSUTF8StringEncoding];count=calls.count;
 i=[WeSVGEngine imageWithData:data size:sz scale:2.25 rotation:0.61 opacity:0.28 color:originalColor];
 CHECK(calls.count==count+1);CHECK(calls.lastObject[@"input"]==data);CHECK(i==lastReturned);metadata(i,sz,2.25);
 CHECK([calls.lastObject[@"angle"]doubleValue]==0.61&&[calls.lastObject[@"alpha"]doubleValue]==0.28);
 CHECK(i.paintedRGB==0x112233&&transforms==0&&forbiddenImageOps==0);
 i=vm(@"direct-vm");CHECK(i.paintedRGB==0x112233&&i==lastReturned);metadata(i,CGSizeMake(23,19),3);
 setting(@"svgTint",@NO);i=vm(@"disabled");CHECK(i.paintedRGB==originalColor.rgb&&calls.lastObject[@"color"]==originalColor);setting(@"svgTint",@YES);
 nonImage=YES;CHECK([(id)vm(@"non-image")isEqual:@"host non-image result"]);nonImage=NO;
}
static void routes(void){
 CGSize s={23,19};NSData*d=[@"svg" dataUsingEncoding:NSUTF8StringEncoding];SVGFixtureConfig*c=config(s,originalColor,0.57,0.3,3);
 NSArray*images=@[[WCSVGImage imageNamed:@"route"],[WCSVGImage imageNamed:@"route" color:originalColor],[WCSVGImage imageNamed:@"route" color:originalColor alpha:0.57],[WCSVGImage imageNamed:@"route" color:originalColor alpha:0.57 rotate:0.3],[WCSVGImage imageNamed:@"route" size:s],[WCSVGImage imageNamed:@"route" size:s color:originalColor],[WCSVGImage imageNamed:@"route" size:s color:originalColor alpha:0.57 rotate:0.3],[WCSVGImage imageWithContentsOfFile:@"file.svg" size:s color:originalColor alpha:0.57 rotate:0.3],[WCSVGImage imageNamed:@"route" fromConfig:c],[WCSVGImage imageData:d fromConfig:c],[WCSVGImage adaptedWeSVGImageWithName:@"route" data:d config:c],[WCSVGImage imageData:d resize:s scale:3]];
 CHECK(images.count==12);for(UIImage*i in images){metadata(i,s,3);CHECK(i.paintedRGB==0x112233);}CHECK(c.color==originalColor&&c.alpha==0.57&&c.rotation==0.3);CHECK(forbiddenImageOps==0);
 // Crucial real route: old name disappears before Engine; scope must preserve policy.
 setting(@"svgExclude",@"engine_named,file.svg");UIImage*i=[WCSVGImage imageNamed:@"engine_named" fromConfig:c];CHECK(i.paintedRGB==originalColor.rgb);
 i=[WCSVGImage imageWithContentsOfFile:@"file.svg" size:s color:originalColor alpha:0.57 rotate:0.3];CHECK(i.paintedRGB==originalColor.rgb);
 setting(@"svgExclude",@"");setting(@"svgInclude",@"engine_named");i=[WCSVGImage imageNamed:@"engine_named" fromConfig:c];CHECK(i.paintedRGB==0x112233);CHECK(vm(@"other").paintedRGB==originalColor.rgb);setting(@"svgInclude",@"");
}
static void refreshAndTransforms(void){
 UIImageView*v=[UIImageView new];UIImage*i=vm(@"refresh");v.image=i;CHECK(v.image.paintedRGB==0x112233);
 v.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;[v traitCollectionDidChange:nil];CHECK(v.image.paintedRGB==0xAABBCC);metadata(v.image,CGSizeMake(23,19),3);
 setting(@"svgTint",@NO);CHECK(v.image.paintedRGB==originalColor.rgb);metadata(v.image,CGSizeMake(23,19),3);
 setting(@"svgTint",@YES);CHECK(v.image.paintedRGB==0xAABBCC);
 UIImage*photo=[UIImage new];photo.paintedRGB=0xFFEEDD;[v replaceOutsideHook:photo];setting(@"svgTintDark",@"#ABCDEF");CHECK(v.image==photo);
 v.image=photo;setting(@"svgTint",@NO);CHECK(v.image==photo);setting(@"svgTint",@YES);setting(@"svgTintDark",@"#AABBCC");
 v.image=nil;CHECK(!v.image);
 // Only transformations explicitly requested by the caller may run, once and in order.
 unsigned before=transforms;i=vm(@"transformed");
 i=[i imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
 i=[i resizableImageWithCapInsets:(UIEdgeInsets){2,4,6,8}];
 i=[i resizableImageWithCapInsets:(UIEdgeInsets){3,5,7,9} resizingMode:UIImageResizingModeStretch];
 i=[i imageWithAlignmentRectInsets:(UIEdgeInsets){9,7,5,3}];
 CHECK(transforms==before+4);CHECK(([i.operations isEqual:@[@"mode:2",@"insets",@"resize:1",@"align"]]));
 v.traitCollection.userInterfaceStyle=UIUserInterfaceStyleLight;v.image=i;
 setting(@"svgTint",@NO);CHECK(v.image.paintedRGB==originalColor.rgb);
 CHECK([v.image.operations isEqual:i.operations]);CHECK(v.image.renderingMode==UIImageRenderingModeAlwaysTemplate);
 CHECK(UIEdgeInsetsEqualToEdgeInsets(v.image.capInsets,((UIEdgeInsets){3,5,7,9})));
 CHECK(UIEdgeInsetsEqualToEdgeInsets(v.image.alignmentRectInsets,((UIEdgeInsets){9,7,5,3})));
 CHECK(CGSizeEqualToSize(v.image.size,i.size)&&v.image.scale==i.scale&&v.image.imageOrientation==i.imageOrientation);
 setting(@"svgTint",@YES);CHECK(v.image.paintedRGB==0x112233);CHECK([v.image.operations isEqual:i.operations]);
 // Independent highlighted and button slots are restored too.
 v.highlightedImage=vm(@"highlighted");UIButton*b=[UIButton new];[b setImage:vm(@"button") forState:5];[b setImage:photo forState:7];
 setting(@"svgTint",@NO);CHECK(v.highlightedImage.paintedRGB==originalColor.rgb);CHECK([b imageForState:5].paintedRGB==originalColor.rgb);CHECK([b imageForState:7]==photo);
 setting(@"svgTint",@YES);CHECK(v.highlightedImage.paintedRGB==0x112233);CHECK([b imageForState:5].paintedRGB==0x112233);CHECK([b imageForState:7]==photo);
 // Same-object UIKit transforms are legal; no copying is necessary for provenance.
 selfTransforms=YES;i=vm(@"self-transform");before=transforms;UIImage*same=[i imageWithRenderingMode:i.renderingMode];same=[same imageWithRenderingMode:same.renderingMode];CHECK(same==i&&transforms==before+2);v.image=same;unsigned noOpTransforms=transforms;setting(@"svgTint",@NO);CHECK(v.image.paintedRGB==originalColor.rgb);CHECK(transforms==noOpTransforms+1);setting(@"svgTint",@YES);CHECK(v.image.paintedRGB==0x112233);CHECK(transforms==noOpTransforms+2);selfTransforms=NO;
 animated=YES;i=vm(@"animation");CHECK(i==lastReturned);CHECK(i.images.count==2&&i.duration==0.8);v.image=i;setting(@"svgTint",@NO);CHECK(v.image.images.count==2&&v.image.duration==0.8&&v.image.paintedRGB==originalColor.rgb);setting(@"svgTint",@YES);animated=NO;
 CHECK(forbiddenImageOps==0);
}
static void selfTransformIntent(void){
 // A no-op on today's factory output can be necessary after replay under
 // another color. Preserve the first explicit Template request, coalesce only
 // the immediately repeated identical request, and still call the host twice.
 modeDependsOnColor=YES;UIImageView*v=[UIImageView new];UIImage*i=vm(@"self-mode-intent");
 CHECK(i.renderingMode==UIImageRenderingModeAlwaysTemplate);unsigned before=transforms;
 UIImage*a=[i imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
 UIImage*b=[a imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
 CHECK(a==i&&b==i);CHECK(transforms==before+2);v.image=b;before=transforms;
 setting(@"svgTint",@NO);CHECK(v.image.paintedRGB==originalColor.rgb);
 CHECK(v.image.renderingMode==UIImageRenderingModeAlwaysTemplate);CHECK(transforms==before+1);
 setting(@"svgTint",@YES);CHECK(v.image.paintedRGB==0x112233);
 CHECK(v.image.renderingMode==UIImageRenderingModeAlwaysTemplate);CHECK(transforms==before+2);
 // Different operations/arguments that happen to return self are not dropped.
 modeDependsOnColor=NO;v.image=nil;selfTransforms=YES;i=vm(@"different-self-steps");
 a=[i imageWithRenderingMode:i.renderingMode];b=[a imageWithAlignmentRectInsets:a.alignmentRectInsets];
 CHECK(a==i&&b==i);v.image=b;before=transforms;setting(@"svgTint",@NO);
 CHECK(v.image.paintedRGB==originalColor.rgb);CHECK(transforms==before+2);
 setting(@"svgTint",@YES);CHECK(v.image.paintedRGB==0x112233);CHECK(transforms==before+4);
 selfTransforms=NO;v.image=nil;
}
static void snapshotAndLifetime(void){
 UIImageView*v=[UIImageView new];NSMutableData*d=[NSMutableData dataWithBytes:"original" length:8];NSData*expected=[d copy];
 UIImage*i=[WeSVGEngine imageWithData:d size:CGSizeMake(23,19) scale:3 rotation:0 opacity:1 color:originalColor];v.image=i;
 [d setData:[@"changed" dataUsingEncoding:NSUTF8StringEncoding]];setting(@"svgTint",@NO);CHECK([calls.lastObject[@"input"]isEqual:expected]);CHECK(v.image.paintedRGB==originalColor.rgb);setting(@"svgTint",@YES);
 __weak UIImage*weakImage;__weak UIImageView*weakView;__weak MMThemeManager*weakManager;
 @autoreleasepool{UIImage*x=vm(@"weak-image");weakImage=x;UIImageView*w=[UIImageView new];weakView=w;w.image=x;MMThemeManager*m=[MMThemeManager new];weakManager=m;w.image=[m svgImageNamed:@"weak-manager" size:CGSizeMake(23,19) color:originalColor alpha:1 angle:0 ignoreNotFound:NO];lastReturned=nil;}
 CHECK(!weakView);CHECK(!weakManager);CHECK(!weakImage);
 // Equal cached outputs remain the same identity, not tagged copies.
 cacheOn=YES;UIImage*a=vm(@"cached"),*b=vm(@"cached");CHECK(a==b);v.image=a;setting(@"svgTint",@NO);CHECK(v.image.paintedRGB==originalColor.rgb);setting(@"svgTint",@YES);CHECK(v.image==a);cacheOn=NO;[cache removeAllObjects];
 // A genuine alias cannot be reclaimed by a third request on the same live
 // object. The quarantine must not hold the UIImage strongly.
 __weak UIImage*weakAlias;
 @autoreleasepool{
  aliasOutput=YES;UIImage*x=vm(@"alias-first");weakAlias=x;v.image=x;
  UIImage*y=vm(@"alias-second");CHECK(x==y);NSUInteger before=calls.count;
  setting(@"svgTintLight",@"#123456");CHECK(calls.count==before);CHECK(v.image==x);
  UIImage*z=vm(@"alias-third");CHECK(z==x);v.image=z;before=calls.count;
  setting(@"svgTintLight",@"#ABCDEF");CHECK(calls.count==before);CHECK(v.image==x);
  aliasOutput=NO;aliasImage=nil;v.image=nil;lastReturned=nil;
 }
 CHECK(!weakAlias);
 // Independent output remains eligible; conflict handling must not disable
 // subsequent ordinary SVGs or restore another request into the old carrier.
 UIImage*recovered=vm(@"alias-recovered");v.image=recovered;NSUInteger before=calls.count;
 setting(@"svgTintLight",@"#345678");CHECK(calls.count==before+1);CHECK(v.image.paintedRGB==0x345678);
 v.image=nil;setting(@"svgTintLight",@"#112233");
}
static void subclassDispatch(void){
 subclassFactory=YES;UIImage*i=vm(@"subclass");i=[i imageWithAlignmentRectInsets:(UIEdgeInsets){5,4,3,2}];CHECK(subclassTransformCalls==1);
 SVGCarrier*v=[SVGCarrier new];v.image=i;CHECK(subclassSetterCalls==1);
 setting(@"svgTint",@NO);CHECK(subclassTransformCalls==2);CHECK(subclassSetterCalls==2);CHECK(v.image.paintedRGB==originalColor.rgb);
 setting(@"svgTint",@YES);CHECK(subclassTransformCalls==3);CHECK(subclassSetterCalls==3);CHECK(v.image.paintedRGB==0x112233);
 CHECK(UIEdgeInsetsEqualToEdgeInsets(v.image.alignmentRectInsets,((UIEdgeInsets){5,4,3,2})));
 subclassFactory=NO;
}
static void setterReentry(void){
 // Begin with a real production slot, then replace it during a new setter's
 // replay. A weak observer proves the old driver/slot association is cleared.
 @autoreleasepool{
  UIImageView*w=[UIImageView new];w.image=vm(@"existing-slot");
  __weak id oldDriver=latestSVGDriver;CHECK(oldDriver);
  w.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;
  UIImage*plain=[UIImage new],*pending=vm(@"superseded-existing-slot");
  unsigned assignmentsBefore=setterAssignments;
  duringFactory=^{w.image=plain;};w.image=pending;
  CHECK(w.image==plain);CHECK(setterAssignments==assignmentsBefore+1);CHECK(!oldDriver);
  NSUInteger callsBefore=calls.count;setting(@"svgTintDark",@"#ABCDEF");
  CHECK(w.image==plain);CHECK(calls.count==callsBefore);setting(@"svgTintDark",@"#AABBCC");
 }
 UIImageView*v=[UIImageView new];v.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;
 UIImage*entry=[UIImage new],*replacement=[UIImage new];v.image=entry;
 UIImage*incoming=vm(@"reentry-new");unsigned before=setterAssignments;
 duringFactory=^{v.image=replacement;};v.image=incoming;
 CHECK(v.image==replacement);CHECK(setterAssignments==before+1);
 // A -> B -> A must supersede the pending assignment despite equal pointers.
 v.image=entry;incoming=vm(@"reentry-aba");before=setterAssignments;
 duringFactory=^{v.image=replacement;v.image=entry;};v.image=incoming;
 CHECK(v.image==entry);CHECK(setterAssignments==before+2);
 setting(@"svgTint",@NO);CHECK(v.image==entry);setting(@"svgTint",@YES);CHECK(v.image==entry);
 // A nested setter on a different slot must not cancel this one.
 incoming=vm(@"reentry-other-slot");before=setterAssignments;
 duringFactory=^{v.highlightedImage=replacement;};v.image=incoming;
 CHECK(v.image.paintedRGB==0xAABBCC);CHECK(v.highlightedImage==replacement);CHECK(setterAssignments==before+1);
 // No reentry: the old current is normally different from the incoming value.
 v.image=entry;incoming=vm(@"ordinary-new-value");before=setterAssignments;v.image=incoming;
 CHECK(v.image.paintedRGB==0xAABBCC);CHECK(setterAssignments==before+1);
 // A throwing ancillary replay after replacement must still unwind its scope.
 incoming=vm(@"reentry-throw");before=setterAssignments;
 duringFactory=^{v.image=replacement;@throw [NSException exceptionWithName:@"ReentrantHost" reason:nil userInfo:nil];};
 v.image=incoming;CHECK(v.image==replacement);CHECK(setterAssignments==before+1);
 v.image=vm(@"after-reentry-throw");CHECK(v.image.paintedRGB==0xAABBCC);
 UIButton*b=[UIButton new];b.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;
 incoming=vm(@"reentry-button");duringFactory=^{[b setImage:replacement forState:7];};[b setImage:incoming forState:5];
 CHECK([b imageForState:5].paintedRGB==0xAABBCC);CHECK([b imageForState:7]==replacement);
 CHECK(!duringFactory);
}
static void failureAndThreads(void){
 throwFactory=YES;BOOL caught=NO;@try{(void)vm(@"throw");}@catch(NSException*e){caught=[e.name isEqual:@"HostFactory"];}CHECK(caught);throwFactory=NO;
 UIImage*i=vm(@"after-throw");CHECK(i.paintedRGB==0x112233);
 returnNil=YES;NSUInteger before=calls.count;i=vm(@"nil-fallback");CHECK(i&&i.paintedRGB==originalColor.rgb);CHECK(calls.count==before+2);returnNil=NO;
 // No implicit UI/trait access during off-main factory calls. Carrier chooses later.
 __block UIImage*background;unsigned readsBefore=traitReads;dispatch_semaphore_t done=dispatch_semaphore_create(0);
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{background=vm(@"background");dispatch_semaphore_signal(done);});
 CHECK(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0);CHECK(traitReads==readsBefore);CHECK(background.paintedRGB==originalColor.rgb);
 UIImageView*v=[UIImageView new];v.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;v.image=background;CHECK(v.image.paintedRGB==0xAABBCC);
 CHECK(forbiddenImageOps==0);
}
int main(int argc,const char**argv){@autoreleasepool{
 CHECK(argc==2);initFixture();NSString*test=[NSString stringWithUTF8String:argv[1]];
 if([test isEqual:@"parameters"])parameters();else if([test isEqual:@"routes"])routes();else if([test isEqual:@"refresh"])refreshAndTransforms();else if([test isEqual:@"self-intent"])selfTransformIntent();else if([test isEqual:@"lifetime"])snapshotAndLifetime();else if([test isEqual:@"subclasses"])subclassDispatch();else if([test isEqual:@"reentry"])setterReentry();else if([test isEqual:@"failures"])failureAndThreads();else CHECK(NO);
 CHECK(forbiddenImageOps==0);printf("SVG PARAM %s %u checks PASS (Foundation model, NOT UIKit/pixels)\n",argv[1],checks);
}return 0;}
