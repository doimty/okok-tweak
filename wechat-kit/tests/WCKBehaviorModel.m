// Compiles actual production keyboard/time/album sources; no device or UIKit.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKPolicy.h"
#import "WCKSettings.h"
#include <stdio.h>
#include <stdlib.h>
static unsigned checks,responderCalls,adjustCalls,updateCalls,experimentCalls;
static BOOL supported=YES,rejectAdjust,denyResponder;
static NSMutableDictionary *statuses;
static WCKSettings *modelStore;
#define CHECK(x) do{++checks;if(!(x)){fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x);abort();}}while(0)
@interface WCKSettings (IsolatedBehaviorStore)
- (instancetype)initWithFileURL:(NSURL *)url;
@end
@interface WCKSettings (IsolatedBehavior)
+ (instancetype)modelShared;
@end
@implementation WCKSettings (IsolatedBehavior)
+ (instancetype)modelShared{return modelStore;}
@end
BOOL WCKHostIsSupported(void){return supported;}
NSDictionary *WCKRuntimeStatuses(void){return statuses.copy;}
void WCKSetModuleStatus(NSString *k,NSString *v){statuses[k]=v;}
BOOL WCKEnabled(NSString *k){NSDictionary*s=WCKSettings.shared.snapshot;return [s[@"enabled"]boolValue]&&[s[k]boolValue];}
BOOL WCKMethodMatches(Class c,SEL s,const char*r,const char*const*a,unsigned n){
 (void)r;(void)a;(void)n;return c&&s&&class_getInstanceMethod(c,s)!=NULL;
}
BOOL WCKInstallHook(Class c,SEL s,IMP imp,IMP*old,const char*r,const char*const*a,unsigned n){
 if((rejectAdjust&&s==NSSelectorFromString(@"adjustTimeLabelLine"))||!WCKMethodMatches(c,s,r,a,n))return NO;
 Method m=class_getInstanceMethod(c,s);*old=method_getImplementation(m);
 if(!class_addMethod(c,s,imp,method_getTypeEncoding(m)))method_setImplementation(m,imp);return YES;
}
@implementation UIResponder
- (BOOL)becomeFirstResponder{self.firstResponder=!denyResponder;return self.firstResponder;}
@end
@implementation UIView
- (instancetype)init{if((self=[super init])){_alpha=1;_bounds=CGRectMake(0,0,50,50);_gestures=[NSMutableArray new];}return self;}
- (void)addGestureRecognizer:(UIGestureRecognizer*)g{[g.view removeGestureRecognizer:g];[self.gestures addObject:g];g.view=self;}
- (void)removeGestureRecognizer:(UIGestureRecognizer*)g{[self.gestures removeObject:g];if(g.view==self)g.view=nil;}
- (void)didMoveToWindow{}
- (void)layoutSubviews{}
- (BOOL)isDescendantOfView:(UIView*)root{for(UIView*v=self;v;v=v.superview)if(v==root)return YES;return NO;}
@end
@implementation UIControl @end
@implementation UILabel @end
@implementation UIViewController @end
@implementation UINavigationController @end
@implementation UITouch @end
@implementation UIGestureRecognizer
- (instancetype)initWithTarget:(id)t action:(SEL)s{if((self=[super init])){_enabled=YES;_actionTarget=t;_action=s;}return self;}
- (void)fire{((void(*)(id,SEL,id))objc_msgSend)(self.actionTarget,self.action,self);}
@end
@implementation UISwipeGestureRecognizer @end
@implementation UIPanGestureRecognizer @end
@implementation UILongPressGestureRecognizer @end
@implementation UIScrollView
- (instancetype)init{if((self=[super init])){_panGestureRecognizer=[[UIPanGestureRecognizer alloc]initWithTarget:nil action:NULL];[self addGestureRecognizer:_panGestureRecognizer];}return self;}
@end
@implementation UIApplication
+ (instancetype)sharedApplication{static UIApplication*a;static dispatch_once_t once;dispatch_once(&once,^{a=[self new];});return a;}
@end
static unsigned dragCalls,toolResponderCalls;
static CGPoint lastVelocity;
static __weak UIScrollView *lastList;
static CGPoint *lastTarget;
@interface BaseMsgContentViewController : UIViewController
@property(nonatomic,strong) id fakeTool;
@property(nonatomic,strong) id inputToolView;
- (id)toolView;
- (void)scrollViewWillEndDragging:(UIScrollView*)scroll withVelocity:(CGPoint)v targetContentOffset:(inout CGPoint*)target;
@end
@implementation BaseMsgContentViewController
- (id)toolView{return self.fakeTool;}
- (void)scrollViewWillEndDragging:(UIScrollView*)scroll withVelocity:(CGPoint)v targetContentOffset:(inout CGPoint*)target{
 ++dragCalls;lastVelocity=v;lastList=scroll;lastTarget=target;if(target){target->x+=7;target->y+=9;}
}
@end
@interface KeyboardText : UIView @end
@implementation KeyboardText
- (BOOL)becomeFirstResponder{++responderCalls;return [super becomeFirstResponder];}
@end
@interface MMInputToolView : UIView
@property(nonatomic,strong) id text;
- (id)textView;
@end
@implementation MMInputToolView
- (id)textView{return self.text;}
- (BOOL)becomeFirstResponder{++toolResponderCalls;return [super becomeFirstResponder];}
@end
@interface WCDataItem : NSObject
@property(nonatomic) unsigned int createtime;
@end
@implementation WCDataItem @end
@interface WCTimeLineCellView : UIView
@property(nonatomic,strong) WCDataItem *m_dataItem;
@property(nonatomic,strong) UILabel *m_timeLabel;
- (void)updateWithDataItem:(id)item actionAreaVM:(id)area;
- (void)adjustTimeLabelLine;
@end
@implementation WCTimeLineCellView
- (instancetype)init{if((self=[super init]))_m_timeLabel=[UILabel new];return self;}
- (void)updateWithDataItem:(id)item actionAreaVM:(id)area{updateCalls++;self.m_dataItem=item;self.m_timeLabel.text=@"host relative time";[self adjustTimeLabelLine];}
- (void)adjustTimeLabelLine{adjustCalls++;}
@end
@interface ExptService : NSObject
- (BOOL)getExpt:(id)key withBoolDef:(BOOL)value;
@end
@implementation ExptService
- (BOOL)getExpt:(id)key withBoolDef:(BOOL)value{experimentCalls++;return value;}
@end
// Capture scheduling only; the production callback body is still executed.
static NSMutableArray *keyboardBlocks;
static int64_t keyboardDelay;
static dispatch_time_t modelDeadline(dispatch_time_t when,int64_t delta){CHECK(when==DISPATCH_TIME_NOW);keyboardDelay=delta;return 777;}
static void modelAfter(dispatch_time_t when,dispatch_queue_t queue,dispatch_block_t block){CHECK(when==777);CHECK(queue==dispatch_get_main_queue());[keyboardBlocks addObject:[block copy]];}
#define dispatch_time modelDeadline
#define dispatch_after modelAfter
#include "WCKKeyboard.m"
#undef dispatch_time
#undef dispatch_after
#include "WCKMomentsTime.m"
// Same on-disk reader against an isolated bundle; never touch the real host plist.
static NSURL *albumBundleURL;
@interface WCKBehaviorBundle : NSBundle
+ (instancetype)mainBundle;
@end
@implementation WCKBehaviorBundle
+ (instancetype)mainBundle{static WCKBehaviorBundle*b;static dispatch_once_t once;dispatch_once(&once,^{b=[self new];});return b;}
- (NSURL*)bundleURL{return albumBundleURL;}
- (NSDictionary*)infoDictionary{return @{@"CFBundleShortVersionString":@"99.0.0"};}
@end
#define NSBundle WCKBehaviorBundle
#include "WCKAlbumSheet.m"
#undef NSBundle
static void set(NSString*k,id v){NSError*e;CHECK([modelStore setObject:v forKey:k error:&e]);CHECK(!e);}
static void drainKeyboard(void){NSArray*blocks=keyboardBlocks.copy;[keyboardBlocks removeAllObjects];for(dispatch_block_t b in blocks)b();}
static void dragTo(BaseMsgContentViewController*vc,UIScrollView*scroll,CGFloat velocity,CGFloat targetY){
 unsigned before=dragCalls;CGPoint point={-77,targetY};lastTarget=NULL;
 [vc scrollViewWillEndDragging:scroll withVelocity:(CGPoint){0.25,velocity} targetContentOffset:&point];
 CHECK(dragCalls==before+1);CHECK(lastList==scroll&&lastTarget==&point);
 CHECK(lastVelocity.x==0.25&&(isnan(velocity)?isnan(lastVelocity.y):lastVelocity.y==velocity));
 CHECK(point.x==-70&&point.y==targetY+9);
}
// Default gesture: released above the bottom, coasts to the very end (500).
static void drag(BaseMsgContentViewController*vc,UIScrollView*scroll,CGFloat velocity){
 dragTo(vc,scroll,velocity,491);
}
int main(int argc,const char **argv){@autoreleasepool{
 CHECK(argc==2);NSString*mode=[NSString stringWithUTF8String:argv[1]];
 statuses=[NSMutableDictionary new];NSString*home=NSProcessInfo.processInfo.environment[@"HOME"];
 CHECK([home containsString:@"wck-behavior-"]);
 albumBundleURL=[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"WeChat.app"] isDirectory:YES];
 CHECK([NSFileManager.defaultManager createDirectoryAtURL:albumBundleURL withIntermediateDirectories:YES attributes:nil error:NULL]);
 NSString*albumVersion=[mode isEqual:@"album_old"]?@"8.0.69":([mode isEqual:@"album_malformed"]?@"Default":@"8.0.76");
 NSDictionary*info=@{@"CFBundleIdentifier":@"com.tencent.xin",@"CFBundleExecutable":@"WeChat",@"CFBundleShortVersionString":albumVersion};
 if(![mode isEqual:@"album_missing"]){NSData*data=[NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];CHECK([data writeToURL:[albumBundleURL URLByAppendingPathComponent:@"Info.plist"] atomically:YES]);}
 modelStore=[[WCKSettings alloc]initWithFileURL:[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"preferences/model.plist"]]];
 Method a=class_getClassMethod(WCKSettings.class,@selector(shared));Method b=class_getClassMethod(WCKSettings.class,@selector(modelShared));method_setImplementation(a,method_getImplementation(b));
 rejectAdjust=[mode isEqual:@"missing_adjust"];WCKInstallKeyboard();WCKInstallMomentsTime();WCKInstallAlbumSheet();
 CHECK([statuses[@"keyboardSwipe"]isEqual:@"ready"]);
 if([mode hasPrefix:@"album_"]){
  CHECK([statuses[@"albumSheet"]isEqual:@"ready"]);
  CHECK(sOriginalAlbumExpt!=NULL);
  ExptService*trial=[ExptService new];set(@"enabled",@YES);set(@"albumSheet",@YES);
  CHECK([trial getExpt:@"clicfg_chat_album_pagesheet_mode" withBoolDef:NO]);
  CHECK(experimentCalls==0);printf("BEHAVIOR album hook attempted without version gate\n");return 0;
 }
 CHECK([statuses[@"albumSheet"]isEqual:@"ready"]);
 if(rejectAdjust){CHECK(![statuses[@"momentsTime"]isEqual:@"ready"]);printf("BEHAVIOR missing adjust rejected\n");return 0;}
 CHECK([statuses[@"momentsTime"]isEqual:@"ready"]);
 keyboardBlocks=[NSMutableArray new];
 BaseMsgContentViewController*vc=[BaseMsgContentViewController new];vc.view=[UIView new];vc.viewLoaded=YES;vc.view.window=[NSObject new];
 MMInputToolView*tool=[MMInputToolView new];KeyboardText*text=[KeyboardText new];tool.text=text;vc.fakeTool=tool;
 UIScrollView*scroll=[UIScrollView new];scroll.window=vc.view.window;scroll.superview=vc.view;
 scroll.bounds=CGRectMake(0,0,320,500);scroll.contentSize=(CGSize){320,1000};scroll.contentOffset=(CGPoint){0,490};
 drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==0);set(@"keyboardSwipe",@YES);drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==0);
 set(@"enabled",@YES);drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==1);CHECK(keyboardDelay==30*NSEC_PER_MSEC);CHECK(responderCalls==0);
 drainKeyboard();CHECK(responderCalls==1&&text.isFirstResponder);CHECK(toolResponderCalls==0);text.firstResponder=NO;
 // Boundary cases: stop>=contentHeight-10, strictly > +0.15, 30ms delay.
 // The stop position decides, not the offset at the moment of release.
 scroll.contentOffset=(CGPoint){0,490};dragTo(vc,scroll,0.6,470);CHECK(keyboardBlocks.count==0);
 // Exactly 15pt short: outside the 10pt tolerance but inside a 20pt one, so this
 // case keeps the tolerance itself under test.
 dragTo(vc,scroll,0.6,476);CHECK(keyboardBlocks.count==0);
 scroll.contentOffset=(CGPoint){0,490};drag(vc,scroll,0.15);CHECK(keyboardBlocks.count==0);
 drag(vc,scroll,-0.6);CHECK(keyboardBlocks.count==0);drag(vc,scroll,NAN);CHECK(keyboardBlocks.count==0);
 drag(vc,scroll,0.15001);CHECK(keyboardBlocks.count==1);drainKeyboard();CHECK(responderCalls==2);text.firstResponder=NO;
 // A flick released well above the bottom that will still coast there must fire;
 // one that stops short must not, whatever its speed.
 scroll.contentOffset=(CGPoint){0,300};dragTo(vc,scroll,0.9,491);CHECK(keyboardBlocks.count==1);drainKeyboard();CHECK(responderCalls==3);text.firstResponder=NO;
 scroll.contentOffset=(CGPoint){0,300};dragTo(vc,scroll,0.9,380);CHECK(keyboardBlocks.count==0);
 scroll.contentOffset=(CGPoint){0,490};
 // The original KVC fallback is used only when toolView returned nil.
 vc.fakeTool=nil;vc.inputToolView=tool;drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==1);drainKeyboard();CHECK(responderCalls==4);text.firstResponder=NO;vc.fakeTool=tool;vc.inputToolView=nil;
 text.firstResponder=YES;drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==0);text.firstResponder=NO;
 tool.text=[NSObject new];drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==0);tool.text=text;
 scroll.superview=nil;drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==0);scroll.superview=vc.view;
 vc.presentedViewController=[UIViewController new];drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==0);vc.presentedViewController=nil;
 UINavigationController*nav=[UINavigationController new];vc.navigationController=nav;nav.topViewController=[UIViewController new];drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==0);nav.topViewController=vc;
 // Cancel delayed work on page leave, preference epoch, responder/target replacement.
 drag(vc,scroll,0.6);vc.view.window=nil;drainKeyboard();CHECK(responderCalls==4);vc.view.window=scroll.window;
 drag(vc,scroll,0.6);set(@"keyboardSwipe",@NO);set(@"keyboardSwipe",@YES);drainKeyboard();CHECK(responderCalls==4);
 drag(vc,scroll,0.6);vc.fakeTool=[MMInputToolView new];drainKeyboard();CHECK(responderCalls==4);vc.fakeTool=tool;
 drag(vc,scroll,0.6);tool.text=[KeyboardText new];drainKeyboard();CHECK(responderCalls==4);tool.text=text;
 drag(vc,scroll,0.6);text.firstResponder=YES;drainKeyboard();CHECK(responderCalls==4);text.firstResponder=NO;
 drag(vc,scroll,0.6);UIApplication.sharedApplication.applicationState=UIApplicationStateBackground;drainKeyboard();CHECK(responderCalls==4);UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
 drag(vc,scroll,0.6);drag(vc,scroll,0.6);CHECK(keyboardBlocks.count==2);drainKeyboard();CHECK(responderCalls==5);text.firstResponder=NO;
 drag(vc,scroll,0.6);drag(vc,scroll,0.1);drainKeyboard();CHECK(responderCalls==5);
 denyResponder=YES;drag(vc,scroll,0.6);drainKeyboard();CHECK(responderCalls==6);CHECK([statuses[@"keyboardSwipe.debug.last"]isEqual:@"聊天文本框拒绝响应"]);denyResponder=NO;
 CHECK(toolResponderCalls==0);CHECK(tool.gestures.count==0&&vc.view.gestures.count==0);
 // Precise album experiment only. Unrelated/nil values preserve original BOOL.
 ExptService*expt=[ExptService new];NSString*key=@"clicfg_chat_album_pagesheet_mode";
 CHECK(![expt getExpt:key withBoolDef:NO]);CHECK(experimentCalls==1);set(@"albumSheet",@YES);
 CHECK([expt getExpt:key withBoolDef:NO]);CHECK(experimentCalls==1);
 CHECK(![expt getExpt:@"other" withBoolDef:NO]);CHECK([expt getExpt:nil withBoolDef:YES]);CHECK(experimentCalls==3);
 set(@"enabled",@NO);CHECK(![expt getExpt:key withBoolDef:NO]);set(@"enabled",@YES);
 // Production formatter, reuse, live toggle, malformed timestamp and host layout.
 WCTimeLineCellView*cell=[WCTimeLineCellView new];WCDataItem*item=[WCDataItem new];item.createtime=1700000000;
 [cell updateWithDataItem:item actionAreaVM:nil];CHECK([cell.m_timeLabel.text isEqual:@"host relative time"]);
 set(@"momentsFormat",@"yyyy-MM-dd HH:mm:ss");set(@"momentsTime",@YES);
 NSString*expected=WCKMomentsFormat(item.createtime);CHECK(expected.length==19);CHECK([cell.m_timeLabel.text isEqual:expected]);CHECK(updateCalls==1);CHECK(adjustCalls>=2);
 set(@"momentsFormat",@"yyyy");CHECK(cell.m_timeLabel.text.length==4);
 set(@"momentsTime",@NO);CHECK([cell.m_timeLabel.text isEqual:@"host relative time"]);
 set(@"momentsTime",@YES);WCDataItem*zero=[WCDataItem new];[cell updateWithDataItem:zero actionAreaVM:nil];CHECK([cell.m_timeLabel.text isEqual:@"host relative time"]);
 [cell updateWithDataItem:item actionAreaVM:nil];CHECK(cell.m_timeLabel.text.length==4);
 cell.m_timeLabel.text=@"another plugin changed this";set(@"momentsTime",@NO);CHECK([cell.m_timeLabel.text isEqual:@"another plugin changed this"]);
 CHECK(!WCKMomentsFormat(0));supported=NO;set(@"momentsTime",@YES);[cell updateWithDataItem:item actionAreaVM:nil];CHECK([cell.m_timeLabel.text isEqual:WCKMomentsFormat(item.createtime)]);
 printf("BEHAVIOR MODEL %u checks PASS (Foundation/model, not UIKit/device)\n",checks);
}return 0;}
