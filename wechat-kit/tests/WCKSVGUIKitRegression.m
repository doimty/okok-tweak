// Standalone iOS/UIKit harness. Not compiled into the tweak. Never runs inside WeChat.
// Build on an iOS simulator and call WCKRunSVGUIKitRegression on the main thread.
#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKPolicy.h"
#import <stdlib.h>
static NSUInteger checks;
#define CHECK(x) do{++checks;if(!(x))@throw [NSException exceptionWithName:@"WCKSVGUIKitRegression" reason:@#x userInfo:nil];}while(0)
static WCKSettings *store;
@interface WCKSettings (UIKitRegressionStore)
- (instancetype)initWithFileURL:(NSURL*)url;
@end
@interface WCKSettings (UIKitRegression)
+ (instancetype)regressionShared;
@end
@implementation WCKSettings (UIKitRegression)
+ (instancetype)regressionShared{return store;}
@end
static NSMutableDictionary *statuses;
BOOL WCKHostIsSupported(void){return YES;}
NSDictionary *WCKRuntimeStatuses(void){return statuses.copy;}
void WCKSetModuleStatus(NSString*k,NSString*v){statuses[k]=v;}
BOOL WCKEnabled(NSString*k){NSDictionary*s=store.snapshot;return [statuses[k]isEqual:@"ready"]&&[s[@"enabled"]boolValue]&&[s[k]boolValue];}
BOOL WCKMethodMatches(Class c,SEL s,const char*r,const char*const*a,unsigned n){Method m=c?class_getInstanceMethod(c,s):NULL;if(!m||method_getNumberOfArguments(m)!=n+2)return NO;char*t=method_copyReturnType(m);BOOL ok=WCKTypeMatches(t,r);free(t);for(unsigned i=0;ok&&i<n;i++){t=method_copyArgumentType(m,i+2);ok=WCKTypeMatches(t,a[i]);free(t);}return ok;}
BOOL WCKInstallHook(Class c,SEL s,IMP p,IMP*o,const char*r,const char*const*a,unsigned n){if(!WCKMethodMatches(c,s,r,a,n))return NO;Method m=class_getInstanceMethod(c,s);*o=method_getImplementation(m);if(!class_addMethod(c,s,p,method_getTypeEncoding(m)))method_setImplementation(m,p);return YES;}
static UIImage *lastHostImage;
static NSUInteger factoryCalls;
static UIImage*hostImage(NSString*name,CGSize size,CGFloat scale,UIColor*color){
 ++factoryCalls;
 // Only the test's simulated host rasterizes. The production tweak must not do so.
 UIGraphicsBeginImageContextWithOptions(size,NO,scale);[color setFill];UIRectFill((CGRect){CGPointZero,size});UIImage*p=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
 UIImage*i=[UIImage imageWithCGImage:p.CGImage scale:scale orientation:UIImageOrientationLeftMirrored];
 i=[i resizableImageWithCapInsets:UIEdgeInsetsMake(1,2,3,4) resizingMode:UIImageResizingModeStretch];
 i=[i imageWithAlignmentRectInsets:UIEdgeInsetsMake(2,1,4,3)];i=[i imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
 if([name isEqual:@"animated"])i=[UIImage animatedImageWithImages:@[i,i] duration:0.6];
 lastHostImage=i;return i;
}
@interface WeSVGVM:NSObject
+ (id)imageWithName:(id)n size:(CGSize)s scale:(double)k rotation:(double)r opacity:(double)a color:(id)c;
@end
@implementation WeSVGVM
+ (id)imageWithName:(id)n size:(CGSize)s scale:(double)k rotation:(double)r opacity:(double)a color:(id)c{return hostImage(n,s,k,c);}
@end
@interface WeSVGEngine:NSObject
+ (id)imageWithData:(id)d size:(CGSize)s scale:(double)k rotation:(double)r opacity:(double)a color:(id)c;
@end
@implementation WeSVGEngine
+ (id)imageWithData:(id)d size:(CGSize)s scale:(double)k rotation:(double)r opacity:(double)a color:(id)c{return hostImage(@"data",s,k,c);}
@end
@interface MMThemeManager:NSObject
- (id)svgImageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a angle:(int)r ignoreNotFound:(BOOL)b;
@end
@implementation MMThemeManager
- (id)svgImageNamed:(id)n size:(CGSize)s color:(id)c alpha:(double)a angle:(int)r ignoreNotFound:(BOOL)b{return [WeSVGVM imageWithName:n size:s scale:3 rotation:r opacity:a color:c];}
@end
static void set(NSString*k,id v){NSError*e=nil;CHECK([store setObject:v forKey:k error:&e]);CHECK(!e);}
static void equalMetadata(UIImage*a,UIImage*b){
 CHECK(CGSizeEqualToSize(a.size,b.size));CHECK(a.scale==b.scale);CHECK(a.imageOrientation==b.imageOrientation);
 CHECK(UIEdgeInsetsEqualToEdgeInsets(a.capInsets,b.capInsets));CHECK(a.resizingMode==b.resizingMode);
 CHECK(UIEdgeInsetsEqualToEdgeInsets(a.alignmentRectInsets,b.alignmentRectInsets));CHECK(a.renderingMode==b.renderingMode);
 CHECK(a.images.count==b.images.count);CHECK(a.duration==b.duration);
 for(NSUInteger n=0;n<a.images.count;n++){CHECK(CGSizeEqualToSize(a.images[n].size,b.images[n].size));CHECK(a.images[n].scale==b.images[n].scale);}
}
NSDictionary *WCKRunSVGUIKitRegression(void){
 CHECK(NSThread.isMainThread);statuses=[NSMutableDictionary new];NSURL*dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
 store=[[WCKSettings alloc]initWithFileURL:[dir URLByAppendingPathComponent:@"model.plist"]];
 Method a=class_getClassMethod(WCKSettings.class,@selector(shared)),b=class_getClassMethod(WCKSettings.class,@selector(regressionShared));method_setImplementation(a,method_getImplementation(b));
 WCKInstallSVG();CHECK([statuses[@"svgTint"]isEqual:@"ready"]);set(@"enabled",@YES);set(@"svgTint",@YES);
 MMThemeManager*m=[MMThemeManager new];
 for(NSString*name in @[@"icon",@"animated"]){
  UIImage*i=[m svgImageNamed:name size:CGSizeMake(23,19) color:UIColor.redColor alpha:0.5 angle:17 ignoreNotFound:NO];CHECK(i==lastHostImage);
  UIImage*expected=i;UIImageView*v=[UIImageView new];v.image=i;equalMetadata(v.image,expected);
  set(@"svgTint",@NO);equalMetadata(v.image,expected);set(@"svgTint",@YES);equalMetadata(v.image,expected);
  if(!i.images.count){
   UIImage*changed=[i imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];changed=[changed resizableImageWithCapInsets:UIEdgeInsetsMake(2,3,4,5) resizingMode:UIImageResizingModeTile];changed=[changed imageWithAlignmentRectInsets:UIEdgeInsetsMake(5,4,3,2)];
   v.image=changed;set(@"svgTint",@NO);equalMetadata(v.image,changed);set(@"svgTint",@YES);equalMetadata(v.image,changed);
  }
 }
 [NSFileManager.defaultManager removeItemAtURL:dir error:NULL];
 return @{@"checks":@(checks),@"factoryCalls":@(factoryCalls),@"level":@"Actual UIKit metadata, isolated fixture; NOT WeChat/device acceptance"};
}
