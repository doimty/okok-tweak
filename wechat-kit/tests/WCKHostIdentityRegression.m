#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "WCKRuntime.h"
#import "WCKEntryRegistry.h"
#import <stdlib.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x); abort(); } } while (0)
@interface IdentityBundleFixture : NSObject
@property (nonatomic,strong) NSURL *bundleURL;
@property (nonatomic,strong) NSURL *executableURL;
@property (nonatomic,copy) NSString *bundleIdentifier;
@property (nonatomic,strong) NSDictionary *displayInfo;
@property (nonatomic) NSUInteger metadataReads;
- (NSDictionary *)infoDictionary;
- (NSString *)bundlePath;
@end
@implementation IdentityBundleFixture
- (NSDictionary *)infoDictionary { ++self.metadataReads; return self.displayInfo; }
- (NSString *)bundlePath { return self.bundleURL.path; }
@end
static IdentityBundleFixture *fixture;
static id fixtureMainBundle(id cls,SEL selector) { return fixture; }
@interface WCKSettingsViewController : NSObject
@end
@implementation WCKSettingsViewController
@end
@interface IdentityPluginModel : NSObject
@property (nonatomic,copy) NSString *controller;
@end
@implementation IdentityPluginModel
@end
@interface WCPluginsMgr : NSObject
@property (nonatomic,strong) NSMutableArray *plugins;
@property (nonatomic) NSUInteger registrations;
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(id)title version:(id)version controller:(id)controller;
@end
@implementation WCPluginsMgr
+ (instancetype)sharedInstance {
    static WCPluginsMgr *mgr; static dispatch_once_t once;
    dispatch_once(&once,^{ mgr=[WCPluginsMgr new];mgr.plugins=[NSMutableArray array]; });return mgr;
}
- (void)registerControllerWithTitle:(id)title version:(id)version controller:(id)controller {
    CHECK(NSThread.isMainThread);
    CHECK([title isEqual:@"WeChatKit"] && [version isEqual:@"0.1.0-alpha4"]);
    CHECK([controller isKindOfClass:NSString.class] && [controller isEqual:@"WCKSettingsViewController"]);
    IdentityPluginModel *model=[IdentityPluginModel new];model.controller=controller;
    [self.plugins addObject:model];++self.registrations;
}
@end
static NSMutableDictionary *validIdentity(void) {
    return [@{@"CFBundleIdentifier":@"com.tencent.xin",@"CFBundleShortVersionString":@"8.0.69",
        @"CFBundleVersion":@"8.0.69.33",@"CFBundleExecutable":@"WeChat"} mutableCopy];
}
static void writeIdentity(id data) {
    NSData *bytes=[NSPropertyListSerialization dataWithPropertyList:data format:NSPropertyListBinaryFormat_v1_0
        options:0 error:NULL];CHECK(bytes);
    CHECK([bytes writeToURL:[fixture.bundleURL URLByAppendingPathComponent:@"Info.plist"] atomically:YES]);
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    CHECK(argc==2);NSString *test=[NSString stringWithUTF8String:argv[1]];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSURL *base=[NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"WeChat.app"] isDirectory:YES];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:NULL]);
    fixture=[IdentityBundleFixture new];fixture.bundleURL=base;
    fixture.executableURL=[base URLByAppendingPathComponent:@"WeChat"];
    fixture.bundleIdentifier=@"com.tencent.xin";fixture.displayInfo=validIdentity();
    CHECK([[NSData data] writeToURL:fixture.executableURL atomically:YES]);
    NSMutableDictionary *disk=validIdentity();BOOL expected=YES,retry=NO;
    if ([test isEqual:@"display_default"] || [test isEqual:@"concurrent"]) {
        NSMutableDictionary *display=validIdentity();display[@"CFBundleShortVersionString"]=@"Default";fixture.displayInfo=display;
    } else if ([test isEqual:@"display_wrong"]) {
        NSMutableDictionary *display=validIdentity();display[@"CFBundleShortVersionString"]=@"9.9.9";display[@"CFBundleVersion"]=@"bad";fixture.displayInfo=display;
    } else if ([test isEqual:@"wrong_build"]) {disk[@"CFBundleVersion"]=@"8.0.70.1";expected=NO;
    } else if ([test isEqual:@"wrong_version"]) {disk[@"CFBundleShortVersionString"]=@"8.0.70";expected=NO;
    } else if ([test isEqual:@"wrong_identifier"]) {disk[@"CFBundleIdentifier"]=@"com.example.Other";expected=NO;
    } else if ([test isEqual:@"runtime_identifier_mismatch"]) {fixture.bundleIdentifier=@"com.example.Other";expected=NO;
    } else if ([test isEqual:@"wrong_executable_name"]) {disk[@"CFBundleExecutable"]=@"Other";expected=NO;
    } else if ([test isEqual:@"wrong_executable_path"]) {fixture.executableURL=[base.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"WeChat"];expected=NO;
    } else if ([test isEqual:@"non_file_url"]) {expected=NO;
    } else if ([test isEqual:@"missing_then_ready"] || [test isEqual:@"corrupt_then_ready"]) {retry=YES;expected=NO;
    } else if ([test isEqual:@"scalar_plist"]) {expected=NO;
    } else if ([test isEqual:@"numeric_version"]) {disk[@"CFBundleShortVersionString"]=@8069;expected=NO;
    } else if ([test isEqual:@"missing_field"]) {[disk removeObjectForKey:@"CFBundleVersion"];expected=NO;
    } else if ([test isEqual:@"oversized"]) {disk[@"Padding"]=[@"x" stringByPaddingToLength:1048577 withString:@"x" startingAtIndex:0];expected=NO;
    } else CHECK([test isEqual:@"normal"]);
    writeIdentity(disk);NSURL *plist=[base URLByAppendingPathComponent:@"Info.plist"];
    if ([test isEqual:@"scalar_plist"]) writeIdentity(@[@"not a dictionary"]);
    if ([test isEqual:@"missing_then_ready"]) CHECK([NSFileManager.defaultManager removeItemAtURL:plist error:NULL]);
    if ([test isEqual:@"corrupt_then_ready"]) CHECK([[@"broken" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:plist atomically:YES]);
    if ([test isEqual:@"non_file_url"]) fixture.bundleURL=[NSURL URLWithString:@"https://invalid.example/WeChat.app"];
    Method mainMethod=class_getClassMethod(NSBundle.class,@selector(mainBundle));CHECK(mainMethod);
    IMP old=method_setImplementation(mainMethod,(IMP)fixtureMainBundle);
    @try {
        CHECK(WCKHostIsSupported()==expected);
        CHECK(WCKRegisterPluginEntry()==expected);
        CHECK(WCPluginsMgr.sharedInstance.registrations==(expected?1u:0u));
        if (retry) {writeIdentity(validIdentity());CHECK(WCKHostIsSupported());CHECK(WCKRegisterPluginEntry());expected=YES;}
        if ([test isEqual:@"concurrent"]) {
            dispatch_apply(32,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^(size_t n){CHECK(WCKHostIsSupported());});
        }
        if (expected) {CHECK(WCKRegisterPluginEntry());CHECK(WCPluginsMgr.sharedInstance.registrations==1);}
        CHECK(fixture.metadataReads==0);
    } @finally { method_setImplementation(mainMethod,old);[NSFileManager.defaultManager removeItemAtPath:path error:NULL]; }
    printf("host identity + actual registry %s PASS\n",argv[1]);
    return 0;
} }
