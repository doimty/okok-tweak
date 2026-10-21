#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "WCKEntryRegistry.h"
#import "WCKRuntime.h"
#import "WCKPolicy.h"
#import <stdlib.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x); abort(); } } while (0)
static BOOL supported = YES, returnNil, dropWrite, throwAfterWrite;
static id shared;
static NSUInteger registrations;
static NSString *lastStatus;
BOOL WCKHostIsSupported(void) { return supported; }
void WCKSetModuleStatus(NSString *key, NSString *status) { lastStatus = status; }
BOOL WCKMethodMatches(Class cls, SEL sel, const char *ret, const char *const *args, unsigned count) {
    Method m = cls ? class_getInstanceMethod(cls,sel) : NULL;
    if (!m || method_getNumberOfArguments(m) != count+2) return NO;
    char *type = method_copyReturnType(m);
    BOOL ok = WCKTypeMatches(type,ret); free(type);
    for (unsigned i=0;ok && i<count;++i) {
        type=method_copyArgumentType(m,i+2); ok=WCKTypeMatches(type,args[i]); free(type);
    }
    return ok;
}
@interface EntryModel : NSObject
@property (nonatomic,strong) id controller;
@end
@implementation EntryModel
@end
@interface WCKSettingsViewController : NSObject
@end
@implementation WCKSettingsViewController
@end
@interface EntryFakeHub : NSObject
@property (nonatomic,strong) id plugins;
+ (id)sharedInstance;
- (void)registerControllerWithTitle:(id)title version:(id)version controller:(id)controller;
@end
@implementation EntryFakeHub
+ (id)sharedInstance { return returnNil ? nil : shared; }
- (void)registerControllerWithTitle:(id)title version:(id)version controller:(id)controller {
    CHECK(NSThread.isMainThread);
    CHECK([title isEqual:@"WeChatKit"] && [version isEqual:@"0.1.0-alpha4"]);
    CHECK([controller isKindOfClass:NSString.class]);
    CHECK([controller isEqual:@"WCKSettingsViewController"]);
    ++registrations;
    if (!dropWrite) { EntryModel *model=[EntryModel new]; model.controller=controller; [self.plugins addObject:model]; }
    if (throwAfterWrite) [NSException raise:@"FixtureFailure" format:@"post-write failure"];
}
@end
static void createHub(BOOL wrongABI) {
    Class cls=objc_allocateClassPair(EntryFakeHub.class,"WCPluginsMgr",0);
    CHECK(cls);
    if (wrongABI) {
        SEL sel=@selector(registerControllerWithTitle:version:controller:);
        IMP imp=class_getMethodImplementation(EntryFakeHub.class,sel);
        CHECK(class_addMethod(cls,sel,imp,"q40@0:8@16@24@32"));
    }
    objc_registerClassPair(cls);
    shared=[cls new]; [shared setPlugins:[NSMutableArray array]];
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    CHECK(argc==2);
    NSString *test=[NSString stringWithUTF8String:argv[1]];
    if ([test isEqual:@"absent_then_late"]) {
        CHECK(!WCKRegisterPluginEntry()); createHub(NO);
        CHECK(WCKRegisterPluginEntry()); CHECK(registrations==1);
    } else {
        BOOL wrongABI=[test isEqual:@"wrong_abi"];
        createHub(wrongABI);
        if ([test isEqual:@"normal"]) {
            CHECK(WCKRegisterPluginEntry()); CHECK(registrations==1);
            CHECK([lastStatus isEqual:@"ready"]);
        } else if ([test isEqual:@"duplicate"]) {
            CHECK(WCKRegisterPluginEntry()); CHECK(WCKRegisterPluginEntry());
            CHECK(registrations==1 && [[shared plugins] count]==1);
        } else if ([test isEqual:@"preserve_neighbor"]) {
            EntryModel *neighbor=[EntryModel new]; neighbor.controller=@"AnotherPluginController";
            [[shared plugins] addObject:neighbor];
            CHECK(WCKRegisterPluginEntry()); CHECK([[shared plugins] count]==2);
            CHECK([[shared plugins] objectAtIndex:0]==neighbor);
        } else if ([test isEqual:@"existing"]) {
            EntryModel *model=[EntryModel new]; model.controller=@"WCKSettingsViewController";
            [[shared plugins] addObject:model]; CHECK(WCKRegisterPluginEntry()); CHECK(!registrations);
        } else if ([test isEqual:@"nil_then_ready"]) {
            returnNil=YES; CHECK(!WCKRegisterPluginEntry()); CHECK(!registrations);
            returnNil=NO; CHECK(WCKRegisterPluginEntry()); CHECK(registrations==1);
        } else if ([test isEqual:@"invalid_list"]) {
            [shared setPlugins:@"not an array"]; CHECK(!WCKRegisterPluginEntry()); CHECK(!registrations);
        } else if ([test isEqual:@"unreadable_model"]) {
            [[shared plugins] addObject:[NSObject new]];
            CHECK(!WCKRegisterPluginEntry()); CHECK(!registrations);
        } else if ([test isEqual:@"readback_failure"]) {
            dropWrite=YES; CHECK(!WCKRegisterPluginEntry()); CHECK(registrations==1);
            CHECK(![lastStatus isEqual:@"ready"]);
        } else if ([test isEqual:@"partial_throw"]) {
            throwAfterWrite=YES; CHECK(!WCKRegisterPluginEntry());
            throwAfterWrite=NO; CHECK(WCKRegisterPluginEntry()); CHECK(registrations==1);
        } else if ([test isEqual:@"unsupported"]) {
            supported=NO; CHECK(!WCKRegisterPluginEntry()); CHECK(!registrations);
        } else if ([test isEqual:@"background"]) {
            dispatch_semaphore_t done=dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
                CHECK(!WCKRegisterPluginEntry()); dispatch_semaphore_signal(done);
            });
            CHECK(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0);
            CHECK(!registrations);
        } else if (wrongABI) {
            CHECK(!WCKRegisterPluginEntry()); CHECK(!registrations);
        } else CHECK(NO);
    }
    printf("ENTRY PASS %s\n",argv[1]);
} return 0; }
