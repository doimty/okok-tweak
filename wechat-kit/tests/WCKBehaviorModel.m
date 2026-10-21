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
BOOL WCKEnabled(NSString *k){NSDictionary*s=WCKSettings.shared.snapshot;return supported&&[statuses[k]isEqual:@"ready"]&&[s[@"enabled"]boolValue]&&[s[k]boolValue];}
BOOL WCKMethodMatches(Class c,SEL s,const char*r,const char*const*a,unsigned n){
 Method m=c?class_getInstanceMethod(c,s):NULL;if(!m||method_getNumberOfArguments(m)!=n+2)return NO;
 char*t=method_copyReturnType(m);BOOL ok=WCKTypeMatches(t,r);free(t);
 for(unsigned i=0;ok&&i<n;i++){t=method_copyArgumentType(m,i+2);ok=WCKTypeMatches(t,a[i]);free(t);}return ok;
}
BOOL WCKInstallHook(Class c,SEL s,IMP imp,IMP*old,const char*r,const char*const*a,unsigned n){
 if((rejectAdjust&&s==NSSelectorFromString(@"adjustTimeLabelLine"))||!WCKMethodMatches(c,s,r,a,n))return NO;
 Method m=class_getInstanceMethod(c,s);*old=method_getImplementation(m);
 if(!class_addMethod(c,s,imp,method_getTypeEncoding(m)))method_setImplementation(m,imp);return YES;
}
@implementation UIResponder
- (BOOL)becomeFirstResponder{return !denyResponder;}
@end
@implementation UIView
- (instancetype)init{if((self=[super init])){_alpha=1;_bounds=CGRectMake(0,0,50,50);_gestures=[NSMutableArray new];}return self;}
- (void)addGestureRecognizer:(UIGestureRecognizer*)g{[g.view removeGestureRecognizer:g];[self.gestures addObject:g];g.view=self;}
- (void)removeGestureRecognizer:(UIGestureRecognizer*)g{[self.gestures removeObject:g];if(g.view==self)g.view=nil;}
- (void)didMoveToWindow{}
- (void)layoutSubviews{}
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
@interface BaseMsgContentViewController : UIViewController @end
@implementation BaseMsgContentViewController @end
@interface MMInputToolView : UIView
@property(nonatomic,strong) UIViewController *controller;
@property(nonatomic,strong) UIView *text;
- (id)getViewController;
- (id)getGrowTextView;
@end
@implementation MMInputToolView
- (id)getViewController{return self.controller;}
- (id)getGrowTextView{return self.text;}
- (BOOL)becomeFirstResponder{responderCalls++;return [super becomeFirstResponder];}
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
#include "WCKKeyboard.m"
#include "WCKMomentsTime.m"
#include "WCKAlbumSheet.m"
static void set(NSString*k,id v){NSError*e;CHECK([modelStore setObject:v forKey:k error:&e]);CHECK(!e);}
static BOOL touch(WCKKeyboardDriver*d,UIView*v){UITouch*t=[UITouch new];t.view=v;return [d gestureRecognizer:d.swipe shouldReceiveTouch:t];}
int main(int argc,const char **argv){@autoreleasepool{
 CHECK(argc==2);NSString*mode=[NSString stringWithUTF8String:argv[1]];
 statuses=[NSMutableDictionary new];NSString*home=NSProcessInfo.processInfo.environment[@"HOME"];
 CHECK([home containsString:@"wck-behavior-"]);
 modelStore=[[WCKSettings alloc]initWithFileURL:[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"preferences/model.plist"]]];
 Method a=class_getClassMethod(WCKSettings.class,@selector(shared));Method b=class_getClassMethod(WCKSettings.class,@selector(modelShared));method_setImplementation(a,method_getImplementation(b));
 rejectAdjust=[mode isEqual:@"missing_adjust"];WCKInstallKeyboard();WCKInstallMomentsTime();WCKInstallAlbumSheet();
 CHECK([statuses[@"keyboardSwipe"]isEqual:@"ready"]);CHECK([statuses[@"albumSheet"]isEqual:@"ready"]);
 if(rejectAdjust){CHECK(![statuses[@"momentsTime"]isEqual:@"ready"]);printf("BEHAVIOR missing adjust rejected\n");return 0;}
 CHECK([statuses[@"momentsTime"]isEqual:@"ready"]);
 MMInputToolView*h=[MMInputToolView new];h.window=[NSObject new];h.controller=[BaseMsgContentViewController new];
 UIView*text=[UIView new];text.superview=h;h.text=text;UIScrollView*scroll=[UIScrollView new];scroll.superview=text;
 UIView*deep=[UIView new];deep.superview=scroll;
 [h layoutSubviews];CHECK(h.gestures.count==1);[h didMoveToWindow];[h layoutSubviews];CHECK(h.gestures.count==1);
 WCKKeyboardDriver*d=objc_getAssociatedObject(h,&sKeyboardDriverKey);CHECK(d);CHECK(!d.swipe.enabled);
 set(@"keyboardSwipe",@YES);CHECK(!d.swipe.enabled);set(@"enabled",@YES);CHECK(d.swipe.enabled);
 CHECK(touch(d,deep));CHECK(touch(d,h));CHECK(!touch(d,[UIView new]));CHECK(!touch(d,nil));
 UIControl*button=[UIControl new];button.superview=h;UIView*buttonChild=[UIView new];buttonChild.superview=button;CHECK(!touch(d,buttonChild));
 deep.hidden=YES;CHECK(!touch(d,deep));deep.hidden=NO;
 CHECK([d gestureRecognizer:d.swipe shouldRecognizeSimultaneouslyWithGestureRecognizer:scroll.panGestureRecognizer]);
 UIScrollView*foreign=[UIScrollView new];foreign.superview=h;
 CHECK(![d gestureRecognizer:d.swipe shouldRecognizeSimultaneouslyWithGestureRecognizer:foreign.panGestureRecognizer]);
 UILongPressGestureRecognizer*lp=[[UILongPressGestureRecognizer alloc]initWithTarget:nil action:NULL];lp.view=scroll;
 CHECK(![d gestureRecognizer:d.swipe shouldRecognizeSimultaneouslyWithGestureRecognizer:lp]);
 d.swipe.state=UIGestureRecognizerStateRecognized;[d.swipe fire];CHECK(responderCalls==1);
 h.controller=[UIViewController new];[d.swipe fire];CHECK(responderCalls==1);
 h.controller=[BaseMsgContentViewController new];h.controller.presentedViewController=[UIViewController new];[d.swipe fire];CHECK(responderCalls==1);h.controller.presentedViewController=nil;
 UINavigationController*nav=[UINavigationController new];h.controller.navigationController=nav;nav.topViewController=[UIViewController new];[d.swipe fire];CHECK(responderCalls==1);nav.topViewController=h.controller;
 UIApplication.sharedApplication.applicationState=UIApplicationStateBackground;[d.swipe fire];CHECK(responderCalls==1);UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
 h.hidden=YES;[d.swipe fire];CHECK(responderCalls==1);h.hidden=NO;id window=h.window;h.window=nil;[d.swipe fire];CHECK(responderCalls==1);h.window=window;
 d.swipe.state=UIGestureRecognizerStateBegan;[d.swipe fire];CHECK(responderCalls==1);d.swipe.state=UIGestureRecognizerStateRecognized;
 set(@"keyboardSwipe",@NO);CHECK(!d.swipe.enabled);[d.swipe fire];CHECK(responderCalls==1);
 set(@"keyboardSwipe",@YES);denyResponder=YES;[d.swipe fire];CHECK(responderCalls==2);CHECK([statuses[@"keyboardSwipe.debug.last"]isEqual:@"输入栏拒绝响应"]);denyResponder=NO;
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
 CHECK(!WCKMomentsFormat(0));supported=NO;set(@"momentsTime",@YES);[cell updateWithDataItem:item actionAreaVM:nil];CHECK([cell.m_timeLabel.text isEqual:@"host relative time"]);
 printf("BEHAVIOR MODEL %u checks PASS (Foundation/model, not UIKit/device)\n",checks);
}return 0;}
