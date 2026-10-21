#import <Foundation/Foundation.h>
#import "WCKSVGSelection.h"
#import "WCKSettings.h"

@interface WCKSettings (IsolatedSVGTest)
- (instancetype)initWithFileURL:(NSURL *)url;
@end
#define CHECK(v) do { ++checks; if (!(v)) { fprintf(stderr,"check %u failed: %s\n",checks,#v); abort(); } } while (0)
int main(void) { @autoreleasepool {
    unsigned checks = 0; uint32_t rgb = 0;
    NSMutableDictionary *s = [@{@"enabled":@YES,@"svgTint":@YES,
        @"svgInclude":@"",@"svgExclude":@"",@"svgTintLight":@"#000000",
        @"svgTintDark":@"#07C160"} mutableCopy];
    CHECK(WCKSVGSelectRGB(s,@"icons_outlined_camera",NO,&rgb) && rgb==0);
    CHECK(WCKSVGSelectRGB(s,@"icons_outlined_camera",YES,&rgb) && rgb==0x07C160);
    s[@"enabled"]=@NO; CHECK(!WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    s[@"enabled"]=@YES; s[@"svgTint"]=@NO; CHECK(!WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    s[@"svgTint"]=@YES; s[@"svgExclude"]=@"icon"; CHECK(!WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    s[@"svgExclude"]=@""; s[@"svgInclude"]=@"other"; CHECK(!WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    s[@"svgInclude"]=@" icon "; CHECK(WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    s[@"svgInclude"]=@" , , "; CHECK(WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    CHECK(!WCKSVGSelectRGB(s,@"",NO,&rgb));
    s[@"svgTintLight"]=@"#gggggg"; CHECK(!WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    CHECK(WCKSVGSelectRGB(s,@"icon",YES,&rgb) && rgb==0x07C160);
    s[@"svgTintLight"]=@"#000000"; s[@"svgExclude"]=@123; CHECK(!WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    s[@"svgExclude"]=@""; s[@"enabled"]=@"YES"; CHECK(!WCKSVGSelectRGB(s,@"icon",NO,&rgb));
    NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSURL *url=[dir URLByAppendingPathComponent:@"isolated.plist"];
    WCKSettings *store=[[WCKSettings alloc] initWithFileURL:url]; NSError *error=nil;
    CHECK([store setObject:@YES forKey:@"svgTint" error:&error]);
    CHECK(!WCKSVGSelectRGB(store.snapshot,@"icon",NO,&rgb));
    CHECK([store setObject:@YES forKey:@"enabled" error:&error]);
    CHECK(WCKSVGSelectRGB(store.snapshot,@"icon",NO,&rgb) && rgb==0x07C160);
    CHECK([store setObject:@"#000000" forKey:@"svgTintLight" error:&error]);
    WCKSettings *reloaded=[[WCKSettings alloc] initWithFileURL:url];
    CHECK(WCKSVGSelectRGB(reloaded.snapshot,@"icon",NO,&rgb) && rgb==0);
    CHECK([store setObject:@NO forKey:@"enabled" error:&error]);
    CHECK(!WCKSVGSelectRGB(store.snapshot,@"icon",NO,&rgb));
    [NSFileManager.defaultManager removeItemAtURL:dir error:NULL];
    printf("SVG production selection + real settings: %u assertions PASS\n",checks);
} return 0; }
