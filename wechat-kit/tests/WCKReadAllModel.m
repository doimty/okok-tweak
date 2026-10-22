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
static NSString *throwAt;
static NSUInteger proxySends;
static void fixtureThrow(NSString *stage){if([throwAt isEqual:stage])@throw [NSException exceptionWithName:@"FixtureException" reason:stage userInfo:nil];}
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
- (id)GetUserNamesOnSessionList{fixtureThrow(@"list");return self.list;}
@end
@interface CMessageMgr : NSObject
@property(nonatomic,strong) NSMutableDictionary *counts;
- (unsigned int)GetUnReadCount:(id)name;
- (void)ClearUnRead:(id)name FromID:(unsigned int)from ToID:(unsigned int)to;
@end
@implementation CMessageMgr
- (instancetype)init{if((self=[super init]))_counts=[NSMutableDictionary dictionary];return self;}
- (unsigned int)GetUnReadCount:(id)name{fixtureThrow(fake_clear?@"after":@"before");reads++;return [self.counts[name] unsignedIntValue];}
- (void)ClearUnRead:(id)name FromID:(unsigned int)from ToID:(unsigned int)to{fixtureThrow(@"clear");CHECK(from==0&&to==UINT32_MAX);fake_clear++;if(!dropClear)self.counts[name]=@0;}
@end
static NSUInteger nativeContextCalls;
static BOOL nativeBadSignature;
static id modelDefaultCenter(id cls, SEL selector){fixtureThrow(@"center");return center;}
@interface MMServiceCenter : NSObject
- (id)getService:(Class)cls;
@end
@implementation MMServiceCenter
- (id)getService:(Class)cls{serviceCalls++;fixtureThrow(@"service");return cls==CMessageMgr.class?manager:cls==MMNewSessionMgr.class?sessions:nil;}
@end
// Deliberately unrelated to MMServiceCenter, matching the observed defaultCenter.
@interface MMContext : NSObject
+ (id)currentContext;
@property(nonatomic,copy) NSString *encoding;
@property(nonatomic) BOOL signatureThrows;
- (id)getService:(Class)cls;
@end
@implementation MMContext
+ (id)currentContext{++nativeContextCalls;fixtureThrow(@"native_center");return center;}
+ (NSMethodSignature *)methodSignatureForSelector:(SEL)sel{
 if(nativeBadSignature && sel==@selector(currentContext))return [NSMethodSignature signatureWithObjCTypes:"Q@:"];
 return [super methodSignatureForSelector:sel];
}
- (id)getService:(Class)cls{serviceCalls++;fixtureThrow(@"service");return cls==CMessageMgr.class?manager:cls==MMNewSessionMgr.class?sessions:nil;}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel{
 if(sel==@selector(getService:)){
  if(self.signatureThrows)@throw [NSException exceptionWithName:@"FixtureSignature" reason:nil userInfo:nil];
  if(self.encoding)return self.encoding.length?[NSMethodSignature signatureWithObjCTypes:self.encoding.UTF8String]:nil;
 }
 return [super methodSignatureForSelector:sel];
}
@end
// A genuine Foundation forwarding path: no NSObject impersonator, no unwrap API.
@interface ReadProxy : NSProxy {
 id _target;
}
@property(nonatomic) SEL checkedSelector;
@property(nonatomic,copy) NSString *encoding;
@property(nonatomic) BOOL signatureThrows;
+ (instancetype)wrapping:(id)target;
@end
@implementation ReadProxy
+ (instancetype)wrapping:(id)target{ReadProxy *proxy=[self alloc];proxy->_target=target;return proxy;}
- (BOOL)isKindOfClass:(Class)cls{fixtureThrow(@"kind");return [_target isKindOfClass:cls];}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel{
 if(sel==self.checkedSelector){
  if(self.signatureThrows)@throw [NSException exceptionWithName:@"FixtureSignature" reason:nil userInfo:nil];
  if(self.encoding)return self.encoding.length?[NSMethodSignature signatureWithObjCTypes:self.encoding.UTF8String]:nil;
 }
 return [_target methodSignatureForSelector:sel];
}
- (void)forwardInvocation:(NSInvocation *)invocation{proxySends++;[invocation invokeWithTarget:_target];}
@end
static id info(id name){if([name isKindOfClass:NSString.class])[manager counts][name]=@1;return name ?: [NSNull null];}
int main(int argc,const char **argv){@autoreleasepool{
 CHECK(argc==2);NSString *test=[NSString stringWithUTF8String:argv[1]];
 BOOL native=[test hasPrefix:@"native_"];
 if(!native)CHECK(class_addMethod(object_getClass(MMServiceCenter.class),NSSelectorFromString(@"defaultCenter"),(IMP)modelDefaultCenter,"@@:"));
 nativeBadSignature=[test isEqual:@"native_bad_abi"];
 CMessageMgr *realManager=[CMessageMgr new];MMNewSessionMgr *realSessions=[MMNewSessionMgr new];
 ReadProxy *messageProxy=[ReadProxy wrapping:realManager],*sessionProxy=[ReadProxy wrapping:realSessions];
 center=[test isEqual:@"normal"]?[MMServiceCenter new]:[MMContext new];
 manager=[test isEqual:@"normal"]?(id)realManager:messageProxy;sessions=[test isEqual:@"normal"]?(id)realSessions:sessionProxy;
 CHECK(class_getSuperclass(object_getClass(messageProxy))==NSProxy.class);
 if(![test isEqual:@"normal"]){CHECK(![center isKindOfClass:MMServiceCenter.class]);CHECK([manager isKindOfClass:CMessageMgr.class]);CHECK([sessions isKindOfClass:MMNewSessionMgr.class]);}
 [sessions setList:@[info(@"one")]];
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
 BOOL batch=[@[@"switch_service",@"proxy_replace",@"context_replace",@"proxy_abi_change",@"proxy_signature_late_throw",@"cancel",@"toggle",@"busy",@"snapshot"] containsObject:test];
 if(batch||[test isEqual:@"large"]){NSMutableArray *a=[NSMutableArray array];for(NSUInteger i=0;i<(batch?17:5001);i++)[a addObject:info([NSString stringWithFormat:@"n%lu",(unsigned long)i])];[sessions setList:a];}
 if([test isEqual:@"replacement"]){UIView *next=[UIView new];next.window=bar.window;next.superview=wrapper;bar.tabBarItemViews=@[next,[UIView new],[UIView new],[UIView new]];[bar layoutSubviews];CHECK(first.gestures.count==0);CHECK(next.gestures.count==1);CHECK(next.gestures[0]==press);CHECK(serviceCalls==0);}
 NSMutableString *mutableName=[NSMutableString stringWithString:@"n16"];
 if([test isEqual:@"snapshot"]){NSMutableArray *list=[realSessions.list mutableCopy];list[16]=mutableName;realSessions.list=list;}
 NSString *expectedError=nil;
 if([test isEqual:@"native_nil"]){center=nil;expectedError=@"currentContext 返回空上下文";}
 if([test isEqual:@"native_bad_abi"])expectedError=@"currentContext ABI 不匹配";
 if([test isEqual:@"native_throws"]){throwAt=@"native_center";expectedError=@"异常";}
 if([test hasPrefix:@"context_bad_"]){
  NSDictionary *enc=@{@"return":@"Q@:#",@"argument":@"@@:@",@"arity":@"@@:",@"self":@"@#:#",@"selector":@"@@@#",@"nil":@""};
  [(MMContext *)center setEncoding:enc[[test substringFromIndex:12]]];expectedError=@"getService: ABI";
 }
 if([test isEqual:@"context_signature_throw"]){[(MMContext *)center setSignatureThrows:YES];expectedError=@"服务解析及签名异常";}
 if([test hasPrefix:@"proxy_bad_"]){
  NSArray *parts=[[test substringFromIndex:10] componentsSeparatedByString:@"_"];NSString *method=parts[0],*field=parts[1];
  ReadProxy *proxy=[method isEqual:@"list"]?sessionProxy:messageProxy;
  proxy.checkedSelector=NSSelectorFromString([method isEqual:@"list"]?@"GetUserNamesOnSessionList":[method isEqual:@"count"]?@"GetUnReadCount:":@"ClearUnRead:FromID:ToID:");
  NSDictionary *enc=[method isEqual:@"list"]?@{@"return":@"Q@:",@"arity":@"@@:@",@"nil":@""}:
   [method isEqual:@"count"]?@{@"return":@"i@:@",@"argument":@"I@:#",@"arity":@"I@:",@"nil":@""}:
   @{@"return":@"I@:@II",@"name":@"v@:#II",@"from":@"v@:@QI",@"to":@"v@:@IQ",@"arity":@"v@:@I",@"self":@"v#:@II",@"selector":@"v@@@II",@"nil":@""};
  proxy.encoding=enc[field];CHECK(proxy.encoding!=nil);expectedError=@"ABI 不匹配";
 }
 if([test isEqual:@"proxy_signature_throw"]){messageProxy.checkedSelector=@selector(ClearUnRead:FromID:ToID:);messageProxy.signatureThrows=YES;expectedError=@"服务解析及签名异常";}
 if([test isEqual:@"nil_center"]){center=nil;expectedError=@"空上下文";}
 if([test isEqual:@"nil_manager"]){manager=nil;expectedError=@"CMessageMgr 服务为空";}
 if([test isEqual:@"nil_sessions"]){sessions=nil;expectedError=@"MMNewSessionMgr 服务为空";}
 if([test isEqual:@"wrong_manager"]){manager=[NSObject new];expectedError=@"CMessageMgr 服务类型不匹配";}
 if([test isEqual:@"wrong_sessions"]){sessions=[NSObject new];expectedError=@"MMNewSessionMgr 服务类型不匹配";}
 if([test isEqual:@"nil_list"]){realSessions.list=nil;expectedError=@"会话列表不可用";}
 if([test isEqual:@"wrong_list"]){realSessions.list=@1;expectedError=@"会话列表不可用";}
 if([test hasPrefix:@"throws_"]){throwAt=[test substringFromIndex:7];expectedError=@"异常";}
 press.state=[test isEqual:@"no_begin"]?UIGestureRecognizerStateChanged:UIGestureRecognizerStateBegan;[press fire];
 if(batch){CHECK(fake_clear==16);[press fire];CHECK(fake_clear==16);
  if([test isEqual:@"switch_service"])manager=[CMessageMgr new];
  if([test isEqual:@"proxy_replace"])manager=[ReadProxy wrapping:realManager]; // same target, different wrapper
  if([test isEqual:@"context_replace"])center=[MMContext new];
  if([test isEqual:@"proxy_abi_change"]){messageProxy.checkedSelector=@selector(ClearUnRead:FromID:ToID:);messageProxy.encoding=@"v@:@IQ";}
  if([test isEqual:@"proxy_signature_late_throw"]){sessionProxy.checkedSelector=@selector(GetUserNamesOnSessionList);sessionProxy.signatureThrows=YES;}
  if([test isEqual:@"snapshot"]){[mutableName setString:@"changed"];realSessions.list=@[@"replacement"];}
  if([test isEqual:@"cancel"]){press.state=UIGestureRecognizerStateCancelled;[press fire];}
  if([test isEqual:@"toggle"]){enabled=NO;[[NSNotificationCenter defaultCenter]postNotificationName:WCKSettingsDidChangeNotification object:nil];enabled=YES;}
  [[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  BOOL completed=[@[@"busy",@"snapshot"] containsObject:test];CHECK(fake_clear==(completed?17:16));
  if(completed)CHECK([lastMessage containsString:@"已核实 17"]);
  else if(![test isEqual:@"toggle"])CHECK([lastMessage containsString:@"已停止"]);
 }else if([@[@"normal",@"context_proxy",@"native_context",@"replacement",@"readback",@"duplicate",@"layout_first"] containsObject:test]){CHECK(fake_clear==1);CHECK(reads==2);if(dropClear)CHECK([lastMessage containsString:@"未能核实"]);else CHECK([lastMessage containsString:@"已核实 1"]);if(![test isEqual:@"normal"])CHECK(proxySends>0);}
 else CHECK(fake_clear==([test isEqual:@"throws_after"]?1:0));
 if(!native || nativeBadSignature)CHECK(nativeContextCalls==0);
 else CHECK(nativeContextCalls>0);
 if(expectedError){CHECK([lastMessage containsString:expectedError]);CHECK(![lastMessage containsString:@"已核实"]);}
 if([test hasPrefix:@"context_bad_"]||[test isEqual:@"context_signature_throw"])CHECK(serviceCalls==0);
 if([test hasPrefix:@"proxy_bad_"]||[test isEqual:@"proxy_signature_throw"])CHECK(reads==0);
 printf("READALL MODEL PASS %s fake_clear=%lu (not UIKit/device)\n",argv[1],(unsigned long)fake_clear);
}return 0;}
