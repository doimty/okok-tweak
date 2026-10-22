#import <Foundation/Foundation.h>
#import "WCKSVGSelection.h"
#import "WCKSettings.h"
#import "WCKSVGPalette.h"

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

    // Palette mode: stable per name, alpha applied, fixed flag respected.
    NSMutableDictionary *pal=[[store snapshot] mutableCopy];
    pal[@"enabled"]=@YES; pal[@"svgTint"]=@YES;
    pal[@"svgUseFixedColor"]=@NO;
    pal[@"svgPaletteHexes"]=@[@"#112233",@"#445566",@"#778899"];
    pal[@"svgRandomAlpha"]=@0.5;
    uint32_t a=0,b=0,packed=0;
    CHECK(WCKSVGSelectPacked(pal,@"icons_outlined_camera",NO,&a));
    CHECK(WCKSVGSelectPacked(pal,@"icons_outlined_camera",NO,&b));
    CHECK(a==b);                                   // same icon, same colour
    CHECK(((a>>24)&0xFF)==128);                    // 0.5 alpha packed
    uint32_t ca=0,cb=0,cc=0; double alpha=0;
    WCKSVGUnpack(a,&ca,&alpha);
    CHECK(ca==0x112233||ca==0x445566||ca==0x778899);
    CHECK(alpha>0.49&&alpha<0.51);
    // Distinct names must not all collapse onto slot 0.
    BOOL varied=NO;
    for (NSString *n in @[@"a",@"b",@"c",@"d",@"e",@"f",@"g",@"h"]) {
        CHECK(WCKSVGSelectPacked(pal,n,NO,&packed));
        WCKSVGUnpack(packed,&cb,&alpha);
        if (cb!=ca) varied=YES;
    }
    CHECK(varied);
    // Alpha is clamped into the visible range.
    pal[@"svgRandomAlpha"]=@0.01;
    CHECK(WCKSVGSelectPacked(pal,@"icon",NO,&packed));
    WCKSVGUnpack(packed,&cc,&alpha); CHECK(alpha>=0.2-1e-9);
    pal[@"svgRandomAlpha"]=@5;
    CHECK(WCKSVGSelectPacked(pal,@"icon",NO,&packed));
    WCKSVGUnpack(packed,&cc,&alpha); CHECK(alpha<=1.0+1e-9);
    // An empty or broken palette falls back to the default set instead of disabling tint.
    pal[@"svgPaletteHexes"]=@[];
    CHECK(WCKSVGSelectPacked(pal,@"icon",NO,&packed));
    pal[@"svgPaletteHexes"]=@[@"nope"];
    CHECK(WCKSVGSelectPacked(pal,@"icon",NO,&packed));
    // Fixed flag wins back the fixed pair.
    pal[@"svgUseFixedColor"]=@YES;
    pal[@"svgTintLight"]=@"#ABCDEF";
    CHECK(WCKSVGSelectPacked(pal,@"icon",NO,&packed));
    WCKSVGUnpack(packed,&cc,&alpha);
    CHECK(cc==0xABCDEF); CHECK(alpha==1.0);
    // Hex helpers reject shorthand and misplaced characters.
    CHECK([WCKNormalizeHex(@"abcdef") isEqual:@"#ABCDEF"]);
    CHECK([WCKNormalizeHex(@" #abcdef ") isEqual:@"#ABCDEF"]);
    CHECK(WCKNormalizeHex(@"abc")==nil);
    CHECK(WCKNormalizeHex(@"#abcdef0")==nil);
    CHECK(WCKNormalizeHex(@"#abcdeg")==nil);
    CHECK(WCKDefaultSVGPalette().count>=4);
    printf("SVG production selection + palette + real settings: %u assertions PASS\n",checks);
} return 0; }
