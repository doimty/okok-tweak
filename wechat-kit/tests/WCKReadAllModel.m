// Runs production WCKReadAll.m; fake services never connect to WeChat/device.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKPolicy.h"
#include <stdlib.h>
#include <stdio.h>
#define CHECK(x) do { if(!(x)){fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x);abort();} } while(0)
static BOOL enabled=YES,dropClear;
static NSUInteger fake_clear,reads,serviceCalls;
static NSString *status,*lastMessage;
static id center,manager,sessions;
NSNotificationName const WCKSettingsDidChangeNotification=@"ReadAllFixtureSettings";
BOOL WCKEnabled(NSString *key){return enabled;}
void WCKSetModuleStatus(NSString *key,NSString *value){status=value;}
BOOL WCKMethodMatches(Class cls,SEL sel,const char *ret,const char *const *args,unsigned n){
 Method m=cls?class_getInstanceMethod(cls,sel):NULL;
 if(!m||method_getNumberOfArguments(m)!=n+2)return NO;
 char *t=method_copyReturnType(m);BOOL ok=WCKTypeMatches(t,ret);free(t);
 for(unsigned i=0;ok&&i<n;i++){t=method_copyArgumentType(m,i+2);ok=WCKTypeMatches(t,args[i]);free(t);}return ok;
}
BOOL WCKInstallHook(Class c,SEL s,IMP imp,IMP *old,const char *r,const char *const *a,unsigned n){
 if(!WCKMethodMatches(c,s,r,a,n))return NO;
 Method m=class_getInstanceMethod(c,s);*old=method_getImplementation(m);
 if(!class_addMethod(c,s,imp,method_getTypeEncoding(m)))method_setImplementation(m,imp);return YES;
}
@implementation UIResponder
@end
@implementation UIView
- (instancetype)init{if((self=[super init])){_alpha=1;_bounds=CGRectMake(0,0,50,50);_gestures=[NSMutableArray array];}return self;}
- (void)addGestureRecognizer:(UIGestureRecognizer *)g{if(g){[g.view removeGestureRecognizer:g];[self.gestures addObject:g];g.view=self;}}
- (void)removeGestureRecognizer:(UIGestureRecognizer *)g{[self.gestures removeObject:g];if(g.view==self)g.view=nil;}
- (void)didMoveToWindow{}
- (void)layoutSubviews{}
@end
@implementation UIViewController
- (void)presentViewController:(UIViewController *)c animated:(BOOL)b completion:(void (^)(void))completion{lastMessage=[(UIAlertController *)c message];if(completion)completion();}
@end
@implementation UITabBarController
@end
@implementation UINavigationController
@end
@implementation UITouch
- (CGPoint)locationInView:(UIView *)view{return CGPointMake(5,5);}
@end
@implementation UIGestureRecognizer
- (instancetype)initWithTarget:(id)t action:(SEL)a{if((self=[super init])){_actionTarget=t;_action=a;_enabled=YES;}return self;}
- (void)fire{((void(*)(id,SEL,id))objc_msgSend)(self.actionTarget,self.action,self);}
@end
@implementation UILongPressGestureRecognizer
@end
@implementation UIApplication
+ (instancetype)sharedApplication{static UIApplication *app; if(!app)app=[self new];return app;}
@end
@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)t message:(NSString *)m preferredStyle:(UIAlertControllerStyle)s{UIAlertController *a=[self new];a.message=m;return a;}
- (void)addAction:(UIAlertAction *)a{}
@end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)t style:(UIAlertActionStyle)s handler:(void (^)(UIAlertAction *))h{return [self new];}
@end
@interface NewMainFrameViewController : UIViewController @end
@implementation NewMainFrameViewController @end
@interface MMTabBar : UIView
@property(nonatomic,strong) NSArray *tabBarItemViews;
@end
@implementation MMTabBar @end
@interface MMSessionInfo : NSObject
@property(nonatomic,strong) id m_nsUserName;
@property(nonatomic) unsigned int m_uUnReadCount;
@end
@implementation MMSessionInfo @end
@interface LegacyInfo : NSObject
- (id)m_nsUsrName;
- (unsigned int)m_uUnReadCount;
@end
@implementation LegacyInfo
- (id)m_nsUsrName{return @"one";}
- (unsigned int)m_uUnReadCount{return 1;}
@end
@interface WrongInfo : NSObject
- (id)m_nsUserName;
- (id)m_uUnReadCount;
@end
@implementation WrongInfo
- (id)m_nsUserName{return @"one";}
- (id)m_uUnReadCount{return @1;}
@end
@interface MMNewSessionMgr : NSObject
@property(nonatomic,strong) id list;
- (id)GetUserNamesOnSessionList;
@end
@implementation MMNewSessionMgr
- (id)GetUserNamesOnSessionList{return self.list;}
@end
@interface CMessageMgr : NSObject
@property(nonatomic,strong) NSMutableDictionary *counts;
- (unsigned int)GetUnReadCount:(id)name;
- (void)ClearUnRead:(id)name FromID:(unsigned int)from ToID:(unsigned int)to;
@end
@implementation CMessageMgr
- (instancetype)init{if((self=[super init]))_counts=[NSMutableDictionary dictionary];return self;}
- (unsigned int)GetUnReadCount:(id)name{reads++;return [self.counts[name] unsignedIntValue];}
- (void)ClearUnRead:(id)name FromID:(unsigned int)from ToID:(unsigned int)to{CHECK(from==0&&to==UINT32_MAX);fake_clear++;if(!dropClear)self.counts[name]=@0;}
@end
@interface MMServiceCenter : NSObject
+ (id)defaultCenter;
- (id)getService:(Class)cls;
@end
@implementation MMServiceCenter
+ (id)defaultCenter{return center;}
- (id)getService:(Class)cls{serviceCalls++;return cls==CMessageMgr.class?manager:cls==MMNewSessionMgr.class?sessions:nil;}
@end
static id info(id name){if([name isKindOfClass:NSString.class])[manager counts][name]=@1;return name ?: [NSNull null];}
int main(int argc,const char **argv){@autoreleasepool{
 CHECK(argc==2);NSString *test=[NSString stringWithUTF8String:argv[1]];
 center=[MMServiceCenter new];manager=[CMessageMgr new];sessions=[MMNewSessionMgr new];[sessions setList:@[info(@"one")]];
 MMTabBar *bar=[MMTabBar new];bar.window=[NSObject new];
 UIView *wrapper=[UIView new];wrapper.window=bar.window;wrapper.superview=bar;
 UIView *first=[UIView new];first.window=bar.window;first.superview=wrapper;
 bar.tabBarItemViews=@[first,[UIView new],[UIView new],[UIView new]];
 UITabBarController *tabs=[UITabBarController new];tabs.selectedViewController=[NewMainFrameViewController new];bar.nextResponder=tabs;
 WCKInstallReadAll();CHECK([status isEqual:@"ready"]);if([test isEqual:@"layout_first"])[bar layoutSubviews];else [bar didMoveToWindow];
 CHECK(first.gestures.count==1);UILongPressGestureRecognizer *press=first.gestures[0];
 CHECK(serviceCalls==0);[bar layoutSubviews];CHECK(serviceCalls==0);
 if([test isEqual:@"legacy"])[sessions setList:@[[LegacyInfo new]]];
 if([test isEqual:@"wrong_abi"])[sessions setList:@[[WrongInfo new]]];
 if([test isEqual:@"nil_name"])[sessions setList:@[info(nil)]];
 if([test isEqual:@"wrong_name"])[sessions setList:@[info(@1)]];
 if([test isEqual:@"long_name"])[sessions setList:@[info([@"x" stringByPaddingToLength:513 withString:@"x" startingAtIndex:0])]];
 if([test isEqual:@"duplicate"])[sessions setList:@[info(@"one"),info(@"one")]];
 if([test isEqual:@"disabled"])enabled=NO;
 if([test isEqual:@"nonfirst"])tabs.selectedIndex=1;
 if([test isEqual:@"wrong_page"])tabs.selectedViewController=[UIViewController new];
 if([test isEqual:@"hidden"])first.hidden=YES;
 if([test isEqual:@"readback"])dropClear=YES;
 BOOL batch=[@[@"switch_service",@"cancel",@"toggle",@"busy"] containsObject:test];
 if(batch||[test isEqual:@"large"]){NSMutableArray *a=[NSMutableArray array];for(NSUInteger i=0;i<(batch?17:5001);i++)[a addObject:info([NSString stringWithFormat:@"n%lu",(unsigned long)i])];[sessions setList:a];}
 if([test isEqual:@"replacement"]){UIView *next=[UIView new];next.window=bar.window;next.superview=wrapper;bar.tabBarItemViews=@[next,[UIView new],[UIView new],[UIView new]];[bar layoutSubviews];CHECK(first.gestures.count==0);CHECK(next.gestures.count==1);CHECK(next.gestures[0]==press);CHECK(serviceCalls==0);}
 press.state=[test isEqual:@"no_begin"]?UIGestureRecognizerStateChanged:UIGestureRecognizerStateBegan;[press fire];
 if(batch){CHECK(fake_clear==16);[press fire];CHECK(fake_clear==16);
  if([test isEqual:@"switch_service"])manager=[CMessageMgr new];
  if([test isEqual:@"cancel"]){press.state=UIGestureRecognizerStateCancelled;[press fire];}
  if([test isEqual:@"toggle"]){enabled=NO;[[NSNotificationCenter defaultCenter]postNotificationName:WCKSettingsDidChangeNotification object:nil];enabled=YES;}
  [[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  CHECK(fake_clear==([test isEqual:@"busy"]?17:16));
 }else if([@[@"normal",@"replacement",@"readback",@"duplicate",@"layout_first"] containsObject:test]){CHECK(fake_clear==1);CHECK(reads==2);if(dropClear)CHECK([lastMessage containsString:@"未能核实"]);else CHECK([lastMessage containsString:@"已核实 1"]);}
 else CHECK(fake_clear==0);
 printf("READALL MODEL PASS %s fake_clear=%lu (not UIKit/device)\n",argv[1],(unsigned long)fake_clear);
}return 0;}
