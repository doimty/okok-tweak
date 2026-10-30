// Actual production WCKCorners + Settings/Palette/Policy, Foundation fake UIKit.
// This is an isolation/ownership/hook-target model, NOT UIKit, pixels, WeChat or device coverage.
#import <UIKit/UIKit.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import "WCKPolicy.h"
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned checks;
#define CHECK_ID(tag, expr) do { ++checks; if (!(expr)) { \
    fprintf(stderr, "CORNERS ASSERT[%s] line %d: %s\n", tag, __LINE__, #expr); \
    exit(86); } } while (0)
static BOOL near(CGFloat a, CGFloat b) { return fabs(a-b) < 0.00001; }
static BOOL sameRect(CGRect a, CGRect b) {
    return near(a.origin.x,b.origin.x) && near(a.origin.y,b.origin.y) &&
        near(a.size.width,b.size.width) && near(a.size.height,b.size.height);
}
static BOOL sameColor(CGColorRef a, CGColorRef b) {
    return a == b || (a && b && CGColorEqualToColor(a,b));
}
static CACornerMask const allCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
    kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
static UIColor *rgb(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}
@implementation UIColor
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    UIColor *c = [self new]; c->_fixtureColor = CGColorCreateGenericRGB(r,g,b,a); return c;
}
- (BOOL)getWhite:(CGFloat *)white alpha:(CGFloat *)alpha {
    if (!_fixtureColor) return NO;
    const CGFloat *c=CGColorGetComponents(_fixtureColor);
    size_t n=CGColorGetNumberOfComponents(_fixtureColor);
    if (n==2) { if (white) *white=c[0]; if (alpha) *alpha=c[1]; return YES; }
    if (n==4 && c[0]==c[1] && c[1]==c[2]) { if (white) *white=c[0]; if (alpha) *alpha=c[3]; return YES; }
    return NO;
}
- (BOOL)getRed:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue alpha:(CGFloat *)alpha {
    if (!_fixtureColor) return NO;
    const CGFloat *c=CGColorGetComponents(_fixtureColor);
    if (CGColorGetNumberOfComponents(_fixtureColor)!=4) return NO;
    if (red) *red=c[0]; if (green) *green=c[1]; if (blue) *blue=c[2]; if (alpha) *alpha=c[3];
    return YES;
}
+ (instancetype)colorWithCGColor:(CGColorRef)cg {
    if (!cg) return nil;
    UIColor *c = [self new]; c->_fixtureColor = CGColorCreateCopy(cg); return c;
}
- (CGColorRef)CGColor { return _fixtureColor; }
- (void)dealloc { if (_fixtureColor) CGColorRelease(_fixtureColor); }
+ (instancetype)clearColor { return [self colorWithRed:0 green:0 blue:0 alpha:0]; }
+ (instancetype)whiteColor { return [self colorWithRed:1 green:1 blue:1 alpha:1]; }
+ (instancetype)blackColor { return [self colorWithRed:0 green:0 blue:0 alpha:1]; }
@end
@implementation CALayer
- (instancetype)init { if ((self=[super init])) { _maskedCorners=allCorners; _cornerCurve=@"host"; } return self; }
+ (instancetype)layer { return [self new]; }
- (CGColorRef)borderColor { return _fixtureBorderColor; }
- (void)setBorderColor:(CGColorRef)c {
    if (c) CGColorRetain(c); if (_fixtureBorderColor) CGColorRelease(_fixtureBorderColor); _fixtureBorderColor=c;
}
- (void)dealloc { if (_fixtureBorderColor) CGColorRelease(_fixtureBorderColor); }
@end
@implementation CAShapeLayer @end
@implementation CALayer (FixtureLayerFactory) @end
static NSMutableDictionary *sFixturePathInfo;
@implementation UIBezierPath {
    UIRectCorner _corners;
    CGSize _radii;
}
+ (instancetype)bezierPathWithRoundedRect:(CGRect)rect byRoundingCorners:(UIRectCorner)corners
                             cornerRadii:(CGSize)radii {
    UIBezierPath *path = [self new];
    path->_corners = corners;
    path->_radii = radii;
    (void)rect;
    return path;
}
- (CGPathRef)CGPath {
    void *token = malloc(1);
    if (!sFixturePathInfo) sFixturePathInfo = [NSMutableDictionary dictionary];
    sFixturePathInfo[[NSValue valueWithPointer:token]] =
        @[@(_corners), @(_radii.width), @(_radii.height)];
    return (CGPathRef)token;
}
+ (NSArray *)fixtureInfoForPath:(CGPathRef)path {
    if (!path || !sFixturePathInfo) return nil;
    return sFixturePathInfo[[NSValue valueWithPointer:(void *)path]];
}
@end
@implementation UIResponder @end
@implementation UITraitCollection
- (UIUserInterfaceStyle)userInterfaceStyle { return UIUserInterfaceStyleLight; }
@end
@interface UIView ()
@property(nonatomic, strong) NSMutableArray<UIView *> *fixtureChildren;
@end
@implementation UIView
- (void)didMoveToWindow {}
- (instancetype)init {
    if ((self=[super init])) { _layer=[CALayer new]; _alpha=1; _fixtureChildren=[NSMutableArray new]; }
    return self;
}
- (instancetype)initWithFrame:(CGRect)r { if ((self=[self init])) [self setFrame:r]; return self; }
- (CGRect)frame { return _fixtureFrame; }
- (void)setFrame:(CGRect)r {
    ++_fixtureFrameCalls; _fixtureFrame=r;
    _fixtureBounds=(CGRect){_fixtureBounds.origin,r.size};
}
- (CGRect)bounds { return _fixtureBounds; }
- (void)setBounds:(CGRect)r { _fixtureBounds=r; }
- (NSArray<UIView *> *)subviews { return self.fixtureChildren.copy; }
- (CGPoint)fixtureOriginInWindow {
    CGPoint origin=CGPointZero; UIView *view=self;
    for (NSUInteger depth=0;view && depth<64;++depth,view=view.superview) {
        origin.x += view.frame.origin.x - view.bounds.origin.x;
        origin.y += view.frame.origin.y - view.bounds.origin.y;
    }
    return origin;
}
- (UITraitCollection *)traitCollection { return [UITraitCollection new]; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    CGPoint from=[self fixtureOriginInWindow];
    CGPoint to=view ? [view fixtureOriginInWindow] : CGPointZero;
    return CGRectOffset(rect,from.x-to.x,from.y-to.y);
}
- (void)addSubview:(UIView *)v {
    [self.fixtureChildren addObject:v]; v.superview=self; v.nextResponder=self; v.window=self.window;
}
- (void)setNeedsLayout { ++_fixtureNeedsLayoutCalls; _fixtureNeedsLayout=YES; }
- (void)layoutIfNeeded { if (_fixtureNeedsLayout) { _fixtureNeedsLayout=NO; [self layoutSubviews]; } }
- (void)layoutSubviews { ++_fixtureLayoutCalls; }
@end
@implementation UIWindow @end
@implementation UIScene @end
@implementation UIWindowScene
- (NSArray<UIWindow *> *)windows { return @[]; }
@end
@implementation UIApplication
+ (instancetype)sharedApplication {
    static UIApplication *shared; static dispatch_once_t once;
    dispatch_once(&once, ^{ shared=[self new]; });
    return shared;
}
- (NSSet<UIScene *> *)connectedScenes { return [NSSet set]; }
@end
@implementation UIScrollView @end
@implementation UIButton @end
@implementation UICollectionViewCell @end
@implementation UITableViewCell
- (instancetype)init {
    if ((self=[super init])) {
        _contentView=[UIView new]; [self addSubview:_contentView];
        _backgroundView=[UIView new]; [self addSubview:_backgroundView];
        _selectedBackgroundView=[UIView new]; [self addSubview:_selectedBackgroundView];
    } return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // Host, and only host, determines content geometry from the incoming cell bounds.
    self.contentView.frame=self.bounds;
    dispatch_block_t callback=self.fixtureLayoutCallback;
    self.fixtureLayoutCallback=nil;
    if (callback) callback();
}
- (void)prepareForReuse { ++self.fixtureReuseCalls; }
@end
@implementation UITableView
- (instancetype)init {
    if ((self=[super init])) { _numberOfSections=3; _fixtureRows=@[@1,@3,@0];
        _fixturePaths=[NSMapTable weakToStrongObjectsMapTable]; }
    return self;
}
- (void)beginUpdates { ++self.fixtureBeginUpdates; }
- (void)endUpdates { ++self.fixtureEndUpdates; }
- (NSIndexPath *)indexPathForCell:(UITableViewCell *)c { return [self.fixturePaths objectForKey:c]; }
- (NSInteger)numberOfRowsInSection:(NSInteger)s {
    return s>=0 && s<(NSInteger)self.fixtureRows.count ? self.fixtureRows[(NSUInteger)s].integerValue : 0;
}
@end
@implementation NSIndexPath (WCKCornersFixture)
+ (instancetype)indexPathForRow:(NSInteger)r inSection:(NSInteger)s {
    NSUInteger indexes[2]={(NSUInteger)s,(NSUInteger)r}; return [self indexPathWithIndexes:indexes length:2];
}
- (NSInteger)section { return (NSInteger)[self indexAtPosition:0]; }
- (NSInteger)row { return (NSInteger)[self indexAtPosition:1]; }
@end
@implementation UIViewController
- (instancetype)init { if ((self=[super init])) { _view=[UIView new]; _view.nextResponder=self; } return self; }
@end
// The shared fake UIKit header only declares these; a linked executable needs
// real implementations or the macOS CI link step fails with undefined symbols.
@implementation NewMainFrameViewController @end
@implementation ContactsViewController @end
@implementation FindFriendEntryViewController @end
@implementation MoreViewController @end
@implementation ContactInfoViewController @end
@implementation WCKSettingsViewController @end
@implementation WCKUnknownViewController @end
@implementation MMTableViewCell
- (void)layoutSubviews { [super layoutSubviews]; }
@end
@implementation MMBaseMultiMenuTableViewCell
- (void)setFrame:(CGRect)frame { [super setFrame:frame]; }
- (void)layoutSubviews { [super layoutSubviews]; }
- (void)prepareForReuse { [super prepareForReuse]; }
@end
@implementation MMMultiMenuTableViewCell @end
@implementation UIImageView @end
@implementation MMHeadImageView @end
@implementation TLProfileImageView @end
@implementation FakeHeadImageView @end
@implementation MMMsgContentNavBar @end
@implementation MMNewMsgContentNavBar @end
@implementation MMTabBar @end
@implementation NewMainFrameCell
#if WCK_CORNERS_HOST_OVERRIDE
- (void)setFrame:(CGRect)r { [super setFrame:r]; }
- (void)layoutSubviews { [super layoutSubviews]; }
- (void)prepareForReuse { [super prepareForReuse]; }
#endif
@end
static WCKSettings *store;
static NSMutableDictionary *statuses;
static NSMutableArray<NSDictionary *> *hookTargets;
static BOOL fixtureMainHooksUnavailable;
static BOOL fixtureLateHookUnverified;
static UITableViewCell *fixtureLateProbe;
static NSUInteger fixtureLateProbeCalls;
@interface WCKSettings (CornersPrivateStore)
- (instancetype)initWithFileURL:(NSURL *)url;
@end
@interface WCKSettings (CornersStore)
+ (instancetype)cornersFixtureShared;
@end
@implementation WCKSettings (CornersStore)
+ (instancetype)cornersFixtureShared { return store; }
@end
BOOL WCKHostIsSupported(void) { return YES; }
NSDictionary *WCKRuntimeStatuses(void) { return statuses.copy; }
void WCKSetModuleStatus(NSString *k, NSString *v) { statuses[k]=v; }
BOOL WCKEnabled(NSString *k) {
    NSDictionary *s=WCKSettings.shared.snapshot;
    return [s[@"enabled"] boolValue] && [s[k] boolValue];
}
BOOL WCKMethodMatches(Class c, SEL s, const char *r, const char *const *a, unsigned n) {
    (void)r; (void)a; (void)n;
    return c && s && class_getInstanceMethod(c,s) != NULL;
}
BOOL WCKInstallHook(Class c, SEL s, IMP imp, IMP *old, const char *r, const char *const *a, unsigned n) {
    if (fixtureMainHooksUnavailable && c == NewMainFrameCell.class) return NO;
    BOOL valid=WCKMethodMatches(c,s,r,a,n);
    [hookTargets addObject:@{@"class":c ? NSStringFromClass(c) : @"(nil)",
        @"selector":NSStringFromSelector(s), @"selectorPresent":@(valid)}];
    CHECK_ID("hooks.target-present",valid && imp && old);
    Method m=class_getInstanceMethod(c,s); *old=method_getImplementation(m);
    if (!class_addMethod(c,s,imp,method_getTypeEncoding(m))) method_setImplementation(m,imp);
    // Model the backend publishing a replacement before reporting completion.
    if (fixtureLateProbe && c == NewMainFrameCell.class) {
        if (s == @selector(setFrame:)) [fixtureLateProbe setFrame:CGRectMake(0,0,120,40)];
        else if (s == @selector(layoutSubviews)) [fixtureLateProbe layoutSubviews];
        else if (s == @selector(prepareForReuse)) [fixtureLateProbe prepareForReuse];
        else CHECK_ID("late.known-selector",NO);
        ++fixtureLateProbeCalls;
        if (fixtureLateHookUnverified) return NO;
    }
    return YES;
}
static void setting(NSString *key, id value) {
    NSError *error=nil; CHECK_ID("settings.real-write",[store setObject:value forKey:key error:&error]);
    CHECK_ID("settings.no-error",!error);
}
static void defaults(void) {
    setting(@"enabled",@YES); setting(@"corners",@YES);
    for (NSString *key in @[@"homepageCornerEnabled", @"mainFrameCornerEnabled",
                            @"myPageCornerEnabled", @"friendProfileCornerEnabled",
                            @"discoverPageCornerEnabled", @"tpModeCornerEnabled"])
        setting(key,@YES);
    setting(@"globalCornerMargin",@24); setting(@"globalCornerRadius",@12);
    setting(@"globalCornerSpacing",@0); setting(@"globalCornerFill",@"");
    setting(@"globalCornerStroke",@0); setting(@"globalCornerStrokeColor",@"");
    for (NSString *family in @[@"searchCorner", @"inputCorner", @"topbarCorner", @"toolbarCorner",
                               @"menuCorner", @"plusMenuCorner", @"mainFrameSwipeMenuCorner",
                               @"systemPopupCorner", @"imeKeyboardCorner", @"chatToolbarCorner", @"emojiCorner",
                               @"chatImageCorner", @"chatBubbleCorner", @"chatTimeRoundCorner", @"msgReferCorner",
                               @"systemMessageCorner", @"systemNoticeCorner", @"voiceTranslateCorner",
                               @"momentCorner", @"finderCorner", @"serviceCorner",
                               @"sendPublishButtonCorner", @"avatarCorner", @"profileCorner", @"otherCorner"]) {
        setting([family stringByAppendingString:@"Enabled"],@NO);
        setting([family stringByAppendingString:@"Radius"],@12);
    }
}

@interface WCKCornerScene : NSObject
@property(nonatomic, strong) UIViewController *controller;
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) UITableViewCell *cell;
@property(nonatomic, strong) UIColor *hostColor, *hostBorder;
@end
@implementation WCKCornerScene @end

static WCKCornerScene *sceneWithRows(Class controllerClass, NSInteger row, NSInteger section,
                                     NSInteger rows) {
    WCKCornerScene *s=[WCKCornerScene new];
    s.controller=[controllerClass new];
    s.window=[UIWindow new];
    s.controller.view.window=s.window;
    s.table=[UITableView new];
    s.table.frame=CGRectMake(0,0,420,900);
    s.table.fixtureRows=@[@1,@(rows),@0];
    s.table.superview=s.controller.view;
    s.table.nextResponder=s.controller.view;
    s.table.window=s.window;
    s.cell=[controllerClass isSubclassOfClass:NewMainFrameViewController.class]
        ? [NewMainFrameCell new] : [MMTableViewCell new];
    s.cell.superview=s.table;
    s.cell.nextResponder=s.table;
    s.cell.window=s.window;
    [s.table.fixturePaths setObject:[NSIndexPath indexPathForRow:row inSection:section] forKey:s.cell];
    s.cell.frame=CGRectMake(0,100,420,60);
    s.hostColor=rgb(.2,.3,.4);
    s.hostBorder=rgb(.4,.5,.6);
    s.cell.backgroundColor=s.hostColor;
    for (CALayer *l in @[s.cell.layer,s.cell.backgroundView.layer]) {
        l.cornerRadius=3; l.maskedCorners=allCorners; l.cornerCurve=@"host";
        l.borderWidth=1; l.borderColor=s.hostBorder.CGColor; l.masksToBounds=NO;
    }
    return s;
}
static void layout(WCKCornerScene *s) {
    NSUInteger calls=s.cell.fixtureLayoutCalls;
    [s.cell layoutSubviews];
    CHECK_ID("layout.original-once",s.cell.fixtureLayoutCalls==calls+1);
    CHECK_ID("layout.content-bounds",sameRect(s.cell.contentView.frame,s.cell.bounds));
}
static void setFrameExpect(WCKCornerScene *s, CGRect incoming, CGRect expected, const char *tag) {
    s.cell.frame=incoming;
    CHECK_ID(tag,sameRect(s.cell.frame,expected));
}
static void expectStyle(WCKCornerScene *s, CGFloat radius, UIRectCorner corners,
                        const char *tag) {
    CALayer *maskLayer=s.cell.layer.mask;
    CHECK_ID(tag,[maskLayer isKindOfClass:CAShapeLayer.class]);
    NSArray *info=[UIBezierPath fixtureInfoForPath:((CAShapeLayer *)maskLayer).path];
    CHECK_ID(tag,info!=nil && near([info[1] doubleValue],radius) &&
        [info[0] unsignedIntegerValue]==corners);
    CHECK_ID(tag,sameRect(maskLayer.frame,s.cell.bounds));
}
static void hostStyle(WCKCornerScene *s, const char *tag) {
    CALayer *layer=s.cell.layer;
    CHECK_ID(tag,layer.mask==nil && near(layer.cornerRadius,3) && layer.maskedCorners==allCorners &&
        [layer.cornerCurve isEqual:@"host"] && !layer.masksToBounds);
    CHECK_ID(tag,near(layer.borderWidth,1) && sameColor(layer.borderColor,s.hostBorder.CGColor));
    CHECK_ID(tag,s.cell.backgroundColor==s.hostColor);
}
static CGRect insetFrame(CGRect f, CGFloat margin, CGFloat top, CGFloat bottom) {
    CGRect out=f;
    out.origin.x+=margin; out.size.width-=2*margin;
    out.origin.y+=top; out.size.height-=top+bottom;
    return out;
}

static void geometry(void) {
    setting(@"globalCornerMargin",@31);
    CHECK_ID("settings.margin-max-30",[WCKSettings.shared.snapshot[@"globalCornerMargin"] doubleValue]==30);
    setting(@"globalCornerMargin",@24);
    setting(@"globalCornerSpacing",@8);
    setting(@"globalCornerRadius",@12);

    UIRectCorner top=UIRectCornerTopLeft|UIRectCornerTopRight;
    UIRectCorner bottom=UIRectCornerBottomLeft|UIRectCornerBottomRight;
    CGRect host=CGRectMake(0,100,420,60);

    WCKCornerScene *first=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    setFrameExpect(first,host,insetFrame(host,24,0,0),"geometry.frame");
    CGRect alreadyInset=first.cell.frame;
    setFrameExpect(first,alreadyInset,alreadyInset,"geometry.before-layout-no-double-inset");
    CGRect resized=CGRectMake(0,120,400,60);
    setFrameExpect(first,resized,insetFrame(resized,24,0,0),"geometry.resize");
    alreadyInset=first.cell.frame;
    setFrameExpect(first,alreadyInset,alreadyInset,"geometry.resize-no-double-inset");
    setFrameExpect(first,host,insetFrame(host,24,0,0),"geometry.after-resize");
    layout(first);
    expectStyle(first,12,top,"geometry.first-style");
    CHECK_ID("geometry.clear-content",sameColor(first.cell.contentView.backgroundColor.CGColor,
        [UIColor clearColor].CGColor));

    WCKCornerScene *middle=sceneWithRows(NewMainFrameViewController.class,1,1,3);
    setFrameExpect(middle,host,insetFrame(host,24,0,0),"geometry.middle-frame");
    layout(middle);
    expectStyle(middle,0,0,"geometry.middle-style");

    WCKCornerScene *last=sceneWithRows(NewMainFrameViewController.class,2,1,3);
    setFrameExpect(last,host,insetFrame(host,24,0,0),"geometry.last-frame");
    layout(last);
    expectStyle(last,12,bottom,"geometry.last-style");

    WCKCornerScene *single=sceneWithRows(ContactsViewController.class,0,0,1);
    setFrameExpect(single,host,insetFrame(host,24,0,0),"geometry.single-frame");
    layout(single);
    expectStyle(single,12,UIRectCornerTopLeft|UIRectCornerTopRight|UIRectCornerBottomLeft|UIRectCornerBottomRight,"geometry.single-style");

    // Zero spacing must not leave a hole: the row keeps its full height.
    setting(@"globalCornerSpacing",@0);
    setFrameExpect(first,host,insetFrame(host,24,0,0),"geometry.spacing-zero-frame");
    layout(first);
    expectStyle(first,12,top,"geometry.spacing-zero-style");
    setting(@"globalCornerSpacing",@8);
    setFrameExpect(first,host,insetFrame(host,24,0,0),"geometry.spacing-back-frame");

    // The host may hand the same frame again; insets must not accumulate.
    for (unsigned i=0;i<20;++i) setFrameExpect(first,host,insetFrame(host,24,0,0),"geometry.stable");
    layout(first);

    // Narrow rows clamp the margin instead of producing a negative width.
    WCKCornerScene *narrow=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    narrow.cell.frame=CGRectMake(40,100,20,60);
    CHECK_ID("geometry.narrow-card",narrow.cell.frame.size.width>=1 && narrow.cell.frame.size.height>0);
    layout(narrow);
    NSArray *narrowInfo=[UIBezierPath fixtureInfoForPath:((CAShapeLayer *)narrow.cell.layer.mask).path];
    CHECK_ID("geometry.narrow-radius",narrowInfo!=nil &&
        [narrowInfo[1] doubleValue]<=
        MIN(narrow.cell.bounds.size.width,narrow.cell.bounds.size.height)/2.0+0.001);

    // Disabling restores both the frame and the layer.
    setting(@"corners",@NO);
    setFrameExpect(first,host,host,"geometry.disabled-frame");
    layout(first);
    hostStyle(first,"geometry.disabled-style");
}

static void isolation(void) {
    // Unknown controllers are outside every page gate.
    WCKCornerScene *unknown=sceneWithRows(WCKUnknownViewController.class,0,1,3);
    setFrameExpect(unknown,CGRectMake(0,100,420,60),CGRectMake(0,100,420,60),"isolation.page-off-frame");
    layout(unknown);
    hostStyle(unknown,"isolation.page-off-style");

    // Generic views outside the cell path keep their own layer untouched.
    setting(@"corners",@YES);
    UIImageView *image=[UIImageView new];
    image.layer.cornerRadius=4;
    image.frame=CGRectMake(0,0,40,40);
    [image layoutSubviews];
    CHECK_ID("isolation.image-layer",near(image.layer.cornerRadius,4));
    UIButton *button=[UIButton new];
    button.backgroundColor=rgb(.9,.9,.9);
    button.frame=CGRectMake(0,0,80,30);
    [button layoutSubviews];
    CHECK_ID("isolation.button-fill",sameColor(button.backgroundColor.CGColor,rgb(.9,.9,.9).CGColor));
}

static void restore(void) {
    setting(@"globalCornerSpacing",@8);
    CGRect host=CGRectMake(0,100,420,60);
    WCKCornerScene *s=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    setFrameExpect(s,host,insetFrame(host,24,0,0),"restore.inset");
    layout(s);
    expectStyle(s,12,UIRectCornerTopLeft|UIRectCornerTopRight,"restore.applied");

    setting(@"corners",@NO);
    setFrameExpect(s,host,host,"restore.frame");
    layout(s);
    hostStyle(s,"restore.host-values");

    setting(@"corners",@YES);
    setFrameExpect(s,host,insetFrame(host,24,0,0),"reuse.inset-before");
    layout(s);
    [s.cell prepareForReuse];
    CHECK_ID("reuse.reuse-called",s.cell.fixtureReuseCalls==1);
    hostStyle(s,"reuse.host-style");
    // A dequeued cell starts from the host state until the table re-frames it.
    setFrameExpect(s,host,insetFrame(host,24,0,0),"reuse.inset-after");
    layout(s);
    expectStyle(s,12,UIRectCornerTopLeft|UIRectCornerTopRight,"reuse.reapplied");
}

static void drainRefresh(void) {
    __block BOOL finished=NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished=YES; });
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && [limit timeIntervalSinceNow]>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    CHECK_ID("refresh.main-queue-drained",finished);
}
static void refresh(void) {
    setting(@"globalCornerSpacing",@8);
    CGRect host=CGRectMake(0,100,420,60);
    WCKCornerScene *s=sceneWithRows(NewMainFrameViewController.class,0,1,3);
    setFrameExpect(s,host,insetFrame(host,24,0,0),"refresh.initial-frame");
    layout(s);
    expectStyle(s,12,UIRectCornerTopLeft|UIRectCornerTopRight,"refresh.initial");
    NSUInteger needs=s.cell.fixtureNeedsLayoutCalls;
    setting(@"globalCornerRadius",@18);
    WCKRefreshCorners();
    drainRefresh();
    CHECK_ID("refresh.registered",s.cell.fixtureNeedsLayoutCalls==needs+1);
    layout(s);
    expectStyle(s,18,UIRectCornerTopLeft|UIRectCornerTopRight,"refresh.radius");
    setting(@"globalCornerRadius",@12);
    setting(@"corners",@NO);
    WCKRefreshCorners();
    drainRefresh();
    layout(s);
    hostStyle(s,"refresh.off-restored");
}

static void lifetime(void) {
    __weak UITableViewCell *weakCell=nil;
    @autoreleasepool {
        WCKCornerScene *s=sceneWithRows(NewMainFrameViewController.class,0,1,3);
        layout(s);
        weakCell=s.cell;
        CHECK_ID("lifetime.alive",weakCell!=nil);
    }
    CHECK_ID("lifetime.weak",weakCell==nil);
    WCKRefreshCorners();
    drainRefresh();
}

static void lateHooks(BOOL unverified) {
    fixtureMainHooksUnavailable=NO;
    fixtureLateProbe=[NewMainFrameCell new];
    fixtureLateHookUnverified=unverified;
    fixtureLateProbeCalls=0;
    WCKInstallCornersLate();
    CHECK_ID("late.published-and-called",fixtureLateProbeCalls==3);
    NSUInteger frames=fixtureLateProbe.fixtureFrameCalls;
    NSUInteger layouts=fixtureLateProbe.fixtureLayoutCalls;
    NSUInteger reuses=fixtureLateProbe.fixtureReuseCalls;
    [fixtureLateProbe setFrame:CGRectMake(0,0,120,40)];
    [fixtureLateProbe layoutSubviews];
    [fixtureLateProbe prepareForReuse];
    CHECK_ID("late.frame-forwarded",fixtureLateProbe.fixtureFrameCalls==frames+1);
    CHECK_ID("late.layout-forwarded",fixtureLateProbe.fixtureLayoutCalls==layouts+1);
    CHECK_ID("late.reuse-forwarded",fixtureLateProbe.fixtureReuseCalls==reuses+1);
    fixtureLateProbe=nil;
}

static void abi(void) {
    CHECK_ID("hooks.nonempty",hookTargets.count>0);
    for (NSDictionary *entry in hookTargets) {
        NSString *c=entry[@"class"], *sel=entry[@"selector"];
        BOOL cellTarget=[@[@"UITableViewCell",@"MMTableViewCell",@"MMMultiMenuTableViewCell",@"NewMainFrameCell"] containsObject:c];
        BOOL pageTarget=[@[@"NewMainFrameViewController",@"ContactsViewController",
                           @"FindFriendEntryViewController",@"MoreViewController",
                           @"ContactInfoViewController"] containsObject:c];
        BOOL verifiedTarget=[@[@"MMHeadImageView", @"TLProfileImageView", @"FakeHeadImageView",
                              @"MMMsgContentNavBar", @"MMNewMsgContentNavBar", @"MMTabBar"] containsObject:c];
        BOOL viewTarget=[c isEqual:@"UIView"];
        BOOL allowedSelector=viewTarget
            ? ([sel isEqual:@"didMoveToWindow"] || [sel isEqual:@"setBackgroundColor:"] ||
               [sel isEqual:@"layoutSubviews"])
            : pageTarget ? [sel isEqual:@"tableView:heightForRowAtIndexPath:"]
            : ([sel isEqual:@"setFrame:"] || [sel isEqual:@"layoutSubviews"] ||
               [sel isEqual:@"prepareForReuse"]);
        CHECK_ID("abi.allowed-target",(cellTarget || pageTarget || verifiedTarget || viewTarget) &&
            allowedSelector);
        CHECK_ID("abi.selector-present",[entry[@"selectorPresent"] boolValue]);
    }
    // The frame hook is the point of this design: the row must arrive pre-inset.
    CHECK_ID("abi.frame",WCKMethodMatches(UITableViewCell.class,@selector(setFrame:),
        @encode(void),(const char *[]){@encode(CGRect)},1));
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK_ID("fixture.argument",argc==2);
        CHECK_ID("fixture.main-thread",NSThread.isMainThread);
        NSString *home=NSProcessInfo.processInfo.environment[@"HOME"];
        CHECK_ID("fixture.isolated-home",home.length>0 && [home.lastPathComponent hasPrefix:@"corners-"]);
        NSURL *file=[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Preferences/corners.plist"]];
        store=[[WCKSettings alloc] initWithFileURL:file];
        Method shared=class_getClassMethod(WCKSettings.class,@selector(shared));
        Method replacement=class_getClassMethod(WCKSettings.class,@selector(cornersFixtureShared));
        method_exchangeImplementations(shared,replacement);
        statuses=[NSMutableDictionary new];
        hookTargets=[NSMutableArray new];
        defaults();
        NSString *which=[NSString stringWithUTF8String:argv[1]];
        BOOL late=[which isEqual:@"late-install"] || [which isEqual:@"late-unverified"];
        fixtureMainHooksUnavailable=late;
        WCKInstallCorners();
        if (!late) CHECK_ID("install.ready",[statuses[@"corners"] isEqual:@"ready"]);
        if ([which isEqual:@"geometry"]) geometry();
        else if ([which isEqual:@"isolation"]) isolation();
        else if ([which isEqual:@"restore"]) restore();
        else if ([which isEqual:@"refresh"]) refresh();
        else if ([which isEqual:@"lifetime"]) lifetime();
        else if ([which isEqual:@"abi"]) abi();
        else if ([which isEqual:@"late-install"]) lateHooks(NO);
        else if ([which isEqual:@"late-unverified"]) lateHooks(YES);
        else CHECK_ID("fixture.known-case",NO);
        NSData *data=[NSJSONSerialization dataWithJSONObject:hookTargets options:0 error:NULL];
        printf("HOOK_TARGETS %s\n",[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String]);
        printf("CORNERS CASE %s PASS (%u checks)\n",argv[1],checks);
    } return 0;
}
