// Actual production WCKCorners + Settings/Palette/Policy, Foundation fake UIKit.
// This is an isolation/ownership/ABI model, NOT UIKit, pixels, WeChat or device coverage.
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
- (CGColorRef)borderColor { return _fixtureBorderColor; }
- (void)setBorderColor:(CGColorRef)c {
    if (c) CGColorRetain(c); if (_fixtureBorderColor) CGColorRelease(_fixtureBorderColor); _fixtureBorderColor=c;
}
- (void)dealloc { if (_fixtureBorderColor) CGColorRelease(_fixtureBorderColor); }
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
@implementation MMTableViewCell @end
@implementation MMMultiMenuTableViewCell @end
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
    return [statuses[k] isEqualToString:@"ready"] && [s[@"enabled"] boolValue] && [s[k] boolValue];
}
// Strict encoding equality: do not silently accept q/i, d/f, object/scalar or wrong struct ABIs.
BOOL WCKMethodMatches(Class c, SEL s, const char *r, const char *const *a, unsigned n) {
    Method m=c ? class_getInstanceMethod(c,s) : NULL;
    if (!m || !r || (n && !a) || method_getNumberOfArguments(m)!=n+2) return NO;
    char *t=method_copyReturnType(m); BOOL ok=t && strcmp(t,r)==0; free(t);
    for (unsigned i=0; ok && i<n; ++i) {
        t=method_copyArgumentType(m,i+2); ok=t && a[i] && strcmp(t,a[i])==0; free(t);
    } return ok;
}
BOOL WCKInstallHook(Class c, SEL s, IMP imp, IMP *old, const char *r, const char *const *a, unsigned n) {
    BOOL valid=WCKMethodMatches(c,s,r,a,n);
    [hookTargets addObject:@{@"class":c ? NSStringFromClass(c) : @"(nil)",
        @"selector":NSStringFromSelector(s), @"abiValid":@(valid)}];
    CHECK_ID("hooks.abi",valid && imp && old);
    Method m=class_getInstanceMethod(c,s); *old=method_getImplementation(m);
    if (!class_addMethod(c,s,imp,method_getTypeEncoding(m))) method_setImplementation(m,imp);
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
static WCKCornerScene *scene(Class controllerClass, NSInteger row, NSInteger section) {
    WCKCornerScene *s=[WCKCornerScene new]; s.controller=[controllerClass new];
    s.window=[UIWindow new]; s.controller.view.window=s.window;
    s.table=[UITableView new]; s.table.frame=CGRectMake(0,0,420,900);
    s.table.superview=s.controller.view; s.table.nextResponder=s.controller.view; s.table.window=s.window;
    s.cell=[controllerClass isSubclassOfClass:NewMainFrameViewController.class] ? [NewMainFrameCell new] : [MMTableViewCell new];
    s.cell.superview=s.table; s.cell.nextResponder=s.table; s.cell.window=s.window;
    [s.table.fixturePaths setObject:[NSIndexPath indexPathForRow:row inSection:section] forKey:s.cell];
    // A freshly created cell has a zero frame; give every scene a realistic
    // host frame so style-only checks exercise the real layout path.
    s.cell.frame=CGRectMake(0,100,420,60);
    s.hostColor=rgb(.2,.3,.4); s.hostBorder=rgb(.4,.5,.6);
    s.cell.backgroundColor=s.hostColor;
    for (CALayer *l in @[s.cell.layer,s.cell.backgroundView.layer]) {
        l.cornerRadius=3; l.maskedCorners=allCorners; l.cornerCurve=@"host";
        l.borderWidth=1; l.borderColor=s.hostBorder.CGColor; l.masksToBounds=NO;
    }
    return s;
}
static void frame(WCKCornerScene *s, CGRect incoming, CGRect expected, const char *tag) {
    NSUInteger calls=s.cell.fixtureFrameCalls, content=s.cell.contentView.fixtureFrameCalls;
    s.cell.frame=incoming;
    CHECK_ID("original.setter-once",s.cell.fixtureFrameCalls==calls+1);
    CHECK_ID("content.no-setter-write",s.cell.contentView.fixtureFrameCalls==content);
    CHECK_ID(tag,sameRect(s.cell.frame,expected));
}
static void layout(WCKCornerScene *s) {
    NSUInteger calls=s.cell.fixtureLayoutCalls, content=s.cell.contentView.fixtureFrameCalls;
    [s.cell layoutSubviews];
    CHECK_ID("original.layout-once",s.cell.fixtureLayoutCalls==calls+1);
    CHECK_ID("content.original-only",s.cell.contentView.fixtureFrameCalls==content+1);
    CHECK_ID("content.bounds",sameRect(s.cell.contentView.frame,s.cell.bounds));
    CHECK_ID("layer.no-clipping",!s.cell.layer.masksToBounds && !s.cell.backgroundView.layer.masksToBounds);
    CHECK_ID("layer.content-untouched",s.cell.contentView.layer.cornerRadius==0 &&
        [s.cell.contentView.layer.cornerCurve isEqual:@"host"] && s.cell.contentView.backgroundColor==nil);
    CHECK_ID("layer.selection-not-clipped",!s.cell.selectedBackgroundView.layer.masksToBounds);
}
static void hostStyle(WCKCornerScene *s, const char *tag) {
    for (CALayer *l in @[s.cell.layer,s.cell.backgroundView.layer]) {
        CHECK_ID(tag,near(l.cornerRadius,3) && l.maskedCorners==allCorners && [l.cornerCurve isEqual:@"host"]);
        CHECK_ID(tag,near(l.borderWidth,1) && sameColor(l.borderColor,s.hostBorder.CGColor));
    }
    CHECK_ID(tag,s.cell.backgroundColor==s.hostColor);
}
static void rounded(WCKCornerScene *s) {
    // Every row is a card: all four corners, not just the section's first/last.
    for (CALayer *l in @[s.cell.layer,s.cell.backgroundView.layer]) {
        CHECK_ID("rows.radius",near(l.cornerRadius,12));
        CHECK_ID("rows.mask",l.maskedCorners==allCorners);
        CHECK_ID("rows.curve",[l.cornerCurve isEqual:kCACornerCurveContinuous]);
        CHECK_ID("border.unconfigured",near(l.borderWidth,1) && sameColor(l.borderColor,s.hostBorder.CGColor));
    }
    CALayer *selected=s.cell.selectedBackgroundView.layer;
    CHECK_ID("rows.selection-radius",near(selected.cornerRadius,12));
    CHECK_ID("rows.selection-mask",selected.maskedCorners==allCorners);
    CHECK_ID("rows.selection-curve",[selected.cornerCurve isEqual:kCACornerCurveContinuous]);
    CHECK_ID("fill.default-card",sameColor(s.cell.backgroundColor.CGColor,rgb(1,1,1).CGColor) &&
        sameColor(s.cell.backgroundView.backgroundColor.CGColor,rgb(1,1,1).CGColor));
}
static void geometry(void) {
    WCKCornerScene *s=scene(NewMainFrameViewController.class,0,0);
    setting(@"globalCornerMargin",@31);
    CHECK_ID("settings.margin-max-30",[WCKSettings.shared.snapshot[@"globalCornerMargin"] doubleValue]==30);
    setting(@"globalCornerMargin",@24);
    CGRect original=CGRectMake(0,100,420,60), inset=CGRectMake(24,100,372,60);
    frame(s,original,inset,"geometry.frame"); layout(s); rounded(s);
    for (unsigned i=0;i<50;++i) { frame(s,s.cell.frame,inset,"geometry.no-accumulation"); layout(s); }
    setting(@"globalCornerMargin",@0);
    frame(s,s.cell.frame,original,"geometry.margin-zero-restores"); layout(s);
    setting(@"globalCornerMargin",@24);
    CGRect narrow=CGRectMake(40,100,340,60);
    frame(s,narrow,narrow,"geometry.host-narrow"); layout(s);
    for (NSInteger row=0;row<3;++row) {
        WCKCornerScene *r=scene(ContactsViewController.class,row,1);
        frame(r,original,inset,"geometry.contacts"); layout(r); rounded(r);
    }
    // The UITableView may insert wrapper views. Its bounds and the cell frame
    // then have different coordinate origins; margin is measured after convert.
    WCKCornerScene *wrapped=scene(NewMainFrameViewController.class,0,0);
    UIView *wrapper=[UIView new]; wrapper.frame=CGRectMake(30,0,500,900); wrapper.bounds=CGRectMake(0,0,500,900);
    wrapper.superview=wrapped.table; wrapper.nextResponder=wrapped.table; wrapper.window=wrapped.window;
    wrapped.table.frame=CGRectMake(0,0,420,900); wrapped.table.bounds=CGRectMake(10,0,420,900);
    wrapped.cell.superview=wrapper; wrapped.cell.nextResponder=wrapper;
    frame(wrapped,CGRectMake(-20,100,420,60),CGRectMake(4,100,372,60),"geometry.wrapper-coordinate-conversion");
    layout(wrapped);
    // Reparent an already-inset cell to a new wrapper at the same window origin.
    // Recovery must translate the remembered host baseline, not inset the old
    // applied x=24 frame a second time.
    WCKCornerScene *migrating=scene(NewMainFrameViewController.class,0,0);
    frame(migrating,original,inset,"geometry.migration-initial");
    UITableView *oldTable=migrating.table;
    UITableView *newTable=[UITableView new]; newTable.frame=CGRectMake(0,0,420,900);
    newTable.superview=migrating.controller.view; newTable.nextResponder=migrating.controller.view; newTable.window=migrating.window;
    UIView *newWrapper=[UIView new]; newWrapper.frame=CGRectMake(0,0,420,900); newWrapper.bounds=newWrapper.frame;
    newWrapper.superview=newTable; newWrapper.nextResponder=newTable; newWrapper.window=migrating.window;
    migrating.cell.superview=newWrapper; migrating.cell.nextResponder=newWrapper;
    [newTable.fixturePaths setObject:[NSIndexPath indexPathForRow:0 inSection:0] forKey:migrating.cell];
    migrating.table=newTable;
    frame(migrating,inset,inset,"geometry.migration-no-double-inset");
    CHECK_ID("geometry.migration-keeps-old-table-alive",oldTable!=nil);
    layout(migrating);
    // Same cell superview, new table ancestor. This catches loss of the host
    // baseline when table identity changes but the applied frame still matches.
    WCKCornerScene *sameParent=scene(NewMainFrameViewController.class,0,0);
    frame(sameParent,original,inset,"geometry.same-parent-initial");
    UITableView *previousTable=sameParent.table;
    UIView *sharedWrapper=[UIView new]; sharedWrapper.frame=CGRectMake(0,0,420,900);
    sharedWrapper.bounds=sharedWrapper.frame; sharedWrapper.superview=previousTable;
    sharedWrapper.nextResponder=previousTable; sharedWrapper.window=sameParent.window;
    sameParent.cell.superview=sharedWrapper; sameParent.cell.nextResponder=sharedWrapper;
    layout(sameParent);
    UITableView *replacementTable=[UITableView new]; replacementTable.frame=CGRectMake(0,0,420,900);
    replacementTable.superview=sameParent.controller.view; replacementTable.nextResponder=sameParent.controller.view;
    replacementTable.window=sameParent.window;
    sharedWrapper.superview=replacementTable; sharedWrapper.nextResponder=replacementTable;
    [replacementTable.fixturePaths setObject:[NSIndexPath indexPathForRow:0 inSection:0] forKey:sameParent.cell];
    sameParent.table=replacementTable;
    layout(sameParent);
    setting(@"globalCornerMargin",@0); layout(sameParent);
    CHECK_ID("geometry.same-parent-table-change-restores-host",sameRect(sameParent.cell.frame,original));
    setting(@"globalCornerMargin",@24);
    // A different wrapper origin must compare old/new frames only after both
    // have been converted to the destination parent's coordinate space.
    WCKCornerScene *offsetMigration=scene(NewMainFrameViewController.class,0,0);
    frame(offsetMigration,original,inset,"geometry.offset-migration-initial");
    UIView *oldParent=offsetMigration.cell.superview;
    UITableView *offsetTable=[UITableView new]; offsetTable.frame=CGRectMake(0,0,420,900);
    offsetTable.superview=offsetMigration.controller.view; offsetTable.nextResponder=offsetMigration.controller.view;
    offsetTable.window=offsetMigration.window;
    UIView *offsetWrapper=[UIView new]; offsetWrapper.frame=CGRectMake(30,0,420,900);
    offsetWrapper.bounds=CGRectMake(0,0,420,900); offsetWrapper.superview=offsetTable;
    offsetWrapper.nextResponder=offsetTable; offsetWrapper.window=offsetMigration.window;
    offsetMigration.cell.superview=offsetWrapper; offsetMigration.cell.nextResponder=offsetWrapper;
    [offsetTable.fixturePaths setObject:[NSIndexPath indexPathForRow:0 inSection:0] forKey:offsetMigration.cell];
    offsetMigration.table=offsetTable;
    CGRect translatedApplied=[oldParent convertRect:inset toView:offsetWrapper];
    CGRect translatedHost=[oldParent convertRect:original toView:offsetWrapper];
    frame(offsetMigration,translatedApplied,translatedApplied,"geometry.offset-migration-applied");
    layout(offsetMigration);
    setting(@"globalCornerMargin",@0); layout(offsetMigration);
    CHECK_ID("geometry.offset-parent-change-restores-host",sameRect(offsetMigration.cell.frame,translatedHost));
    setting(@"globalCornerMargin",@24);
    // A host can synchronously lay out another cell during this cell's original
    // layout. Per-cell depth must not suppress that other cell's corner pass.
    WCKCornerScene *outer=scene(NewMainFrameViewController.class,0,0);
    WCKCornerScene *nested=scene(ContactsViewController.class,0,1);
    outer.cell.frame=original; nested.cell.frame=original;
    outer.cell.fixtureLayoutCallback=^{[nested.cell layoutSubviews];};
    layout(outer);
    CHECK_ID("geometry.nested-other-cell",near(nested.cell.frame.origin.x,24) &&
        near(nested.cell.frame.size.width,372) && near(nested.cell.layer.cornerRadius,12));
}
static void isolation(void) {
    NSArray *excluded=@[WCKSettingsViewController.class,WCKUnknownViewController.class];
    setting(@"mainFrameCornerEnabled",@YES);
    {
        for (Class c in excluded) {
            WCKCornerScene *s=scene(c,0,0); CGRect r=CGRectMake(0,100,420,60);
            frame(s,r,r,"isolation.page-frame"); layout(s); hostStyle(s,"isolation.page-style");
        }
        WCKCornerScene *s=scene(NewMainFrameViewController.class,0,0);
        UIButton *b=[UIButton new]; b.superview=s.table; b.nextResponder=s.table; b.window=s.window;
        b.backgroundColor=s.hostColor; b.layer.cornerRadius=3; b.frame=CGRectMake(0,1,420,40);
        [b layoutSubviews];
        CHECK_ID("isolation.button",sameRect(b.frame,CGRectMake(0,1,420,40)) &&
            near(b.layer.cornerRadius,3) && b.backgroundColor==s.hostColor && !b.layer.masksToBounds);
    }
    NSArray *allOnly=@[FindFriendEntryViewController.class,MoreViewController.class,ContactInfoViewController.class];
    for (Class c in allOnly) {
        WCKCornerScene *s=scene(c,0,0);
        setting(@"mainFrameCornerEnabled",@NO);
        frame(s,CGRectMake(0,100,420,60),CGRectMake(0,100,420,60),"scope.page-off");
        layout(s); hostStyle(s,"scope.page-off-host");
        setting(@"mainFrameCornerEnabled",@YES);
        frame(s,CGRectMake(0,100,420,60),CGRectMake(24,100,372,60),"scope.page-on");
        layout(s); rounded(s);
    }
    // Fail-closed: missing window/index path/recognized parent and impossible geometry.
    // A very narrow but otherwise valid table is NOT an invalid case: the module
    // rounds it with a capped radius, so it is asserted separately below.
    for (unsigned kind=0;kind<4;++kind) {
        WCKCornerScene *s=scene(NewMainFrameViewController.class,0,0);
        CGRect r=CGRectMake(0,100,420,60);
        if (kind==0) s.cell.window=nil;
        if (kind==1) [s.table.fixturePaths removeObjectForKey:s.cell];
        if (kind==2) { s.cell.superview=nil; s.cell.nextResponder=nil; }
        if (kind==3) r.size.width=NAN;
        NSUInteger before=s.cell.fixtureFrameCalls; s.cell.frame=r;
        CHECK_ID("invalid.original-once",s.cell.fixtureFrameCalls==before+1);
        if (kind==3) CHECK_ID("invalid.nan",isnan(s.cell.frame.size.width));
        else CHECK_ID("invalid.geometry",sameRect(s.cell.frame,r));
        [s.cell layoutSubviews]; hostStyle(s,"invalid.style");
    }
    // Geometry too narrow for the configured margin: keep the host frame and
    // clamp the radius to half the shorter side instead of skipping rounding.
    WCKCornerScene *narrow=scene(NewMainFrameViewController.class,0,0);
    narrow.table.bounds=CGRectMake(0,0,20,900);
    narrow.cell.frame=CGRectMake(0,100,20,60);
    [narrow.cell layoutSubviews];
    CHECK_ID("geometry.narrow-no-inset",sameRect(narrow.cell.frame,CGRectMake(0,100,20,60)));
    CHECK_ID("geometry.narrow-radius-capped",near(narrow.cell.layer.cornerRadius,10));
    // Vertical card spacing comes from the cell frame, so neighbours cannot
    // share an edge and hide their rounded corners.
    setting(@"globalCornerSpacing",@12);
    WCKCornerScene *spaced=scene(NewMainFrameViewController.class,0,0);
    frame(spaced,CGRectMake(0,100,420,60),CGRectMake(24,106,372,48),"geometry.spacing");
    layout(spaced);
    setting(@"globalCornerSpacing",@0);
    frame(spaced,spaced.cell.frame,CGRectMake(24,100,372,60),"geometry.spacing-cleared");
}

static void restore(void) {
    WCKCornerScene *s=scene(NewMainFrameViewController.class,0,0);
    setting(@"globalCornerFill",@"#123456"); setting(@"globalCornerStroke",@2);
    setting(@"globalCornerStrokeColor",@"#AABBCC");
    frame(s,CGRectMake(0,100,420,60),CGRectMake(24,100,372,60),"restore.initial-frame"); layout(s);
    CHECK_ID("restore.fill-applied",sameColor(s.cell.backgroundColor.CGColor,rgb(18/255.,52/255.,86/255.).CGColor));
    CHECK_ID("restore.border-applied",near(s.cell.layer.borderWidth,2) &&
        sameColor(s.cell.layer.borderColor,rgb(170/255.,187/255.,204/255.).CGColor));
    setting(@"globalCornerFill",@""); setting(@"globalCornerStroke",@0); setting(@"globalCornerStrokeColor",@"");
    layout(s);
    CHECK_ID("restore.default-fill",sameColor(s.cell.backgroundColor.CGColor,rgb(1,1,1).CGColor));
    CHECK_ID("restore.empty-border",near(s.cell.layer.borderWidth,1) && sameColor(s.cell.layer.borderColor,s.hostBorder.CGColor));
    setting(@"corners",@NO); layout(s); hostStyle(s,"restore.off");
    setting(@"corners",@YES); setting(@"globalCornerFill",@"#123456");
    setting(@"globalCornerStroke",@2); setting(@"globalCornerStrokeColor",@"#AABBCC"); layout(s);
    // Host replaces our last-applied values. A following pass must adopt, not erase them.
    UIColor *newHost=rgb(.8,.1,.2), *newBorder=rgb(.7,.2,.9);
    s.cell.backgroundColor=newHost;
    for (CALayer *l in @[s.cell.layer,s.cell.backgroundView.layer]) {
        l.cornerRadius=7; l.maskedCorners=kCALayerMinXMaxYCorner; l.cornerCurve=@"new-host";
        l.borderWidth=3; l.borderColor=newBorder.CGColor;
    }
    layout(s); setting(@"enabled",@NO); layout(s);
    for (CALayer *l in @[s.cell.layer,s.cell.backgroundView.layer]) {
        CHECK_ID("restore.host-new-values",near(l.cornerRadius,7) && l.maskedCorners==kCALayerMinXMaxYCorner &&
            [l.cornerCurve isEqual:@"new-host"] && near(l.borderWidth,3) && sameColor(l.borderColor,newBorder.CGColor));
    }
    CHECK_ID("restore.host-new-bg",s.cell.backgroundColor==newHost);
    defaults(); setting(@"mainFrameCornerEnabled",@NO); s=scene(MoreViewController.class,0,0); layout(s); hostStyle(s,"restore.list-excluded");
    setting(@"mainFrameCornerEnabled",@YES); layout(s); rounded(s);
    // Same cell migrates to an excluded page, not a new cell.
    UIViewController *excluded=[WCKSettingsViewController new];
    s.table.nextResponder=excluded.view; s.table.superview=excluded.view;
    layout(s); hostStyle(s,"restore.page-migration");
    s=scene(NewMainFrameViewController.class,0,0); layout(s);
    NSUInteger before=s.cell.fixtureReuseCalls; [s.cell prepareForReuse];
    CHECK_ID("original.reuse-once",s.cell.fixtureReuseCalls==before+1); hostStyle(s,"restore.reuse");
    // A reuse cannot resurrect the old page's baseline.
    s.cell.backgroundColor=newHost; s.cell.layer.cornerRadius=9;
    setting(@"corners",@NO); layout(s);
    CHECK_ID("restore.reuse-drops-state",s.cell.backgroundColor==newHost && near(s.cell.layer.cornerRadius,9));

    // UIKit may dequeue a detached cell. Its frame remains in the old local
    // coordinate space, so reuse must still return our owned inset to baseline.
    defaults();
    WCKCornerScene *detached=scene(NewMainFrameViewController.class,0,0);
    CGRect original=CGRectMake(0,100,420,60), inset=CGRectMake(24,100,372,60);
    frame(detached,original,inset,"reuse.detached-initial"); layout(detached);
    detached.cell.superview=nil; detached.cell.nextResponder=nil; detached.cell.window=nil;
    [detached.cell prepareForReuse];
    CHECK_ID("reuse.detached-restores-host",sameRect(detached.cell.frame,original));
    hostStyle(detached,"reuse.detached-style");

    // The wrapper can remain the cell's parent while being moved from one
    // table to another. Table identity must not block restoration in the same
    // coordinate system.
    defaults();
    WCKCornerScene *moved=scene(NewMainFrameViewController.class,0,0);
    frame(moved,original,inset,"reuse.table-change-initial");
    UITableView *oldTable=moved.table;
    UIView *wrapper=[UIView new]; wrapper.frame=CGRectMake(0,0,420,900);
    wrapper.bounds=wrapper.frame; wrapper.superview=oldTable; wrapper.nextResponder=oldTable;
    wrapper.window=moved.window; moved.cell.superview=wrapper; moved.cell.nextResponder=wrapper;
    layout(moved);
    UITableView *newTable=[UITableView new]; newTable.frame=CGRectMake(0,0,420,900);
    newTable.superview=moved.controller.view; newTable.nextResponder=moved.controller.view;
    newTable.window=moved.window; wrapper.superview=newTable; wrapper.nextResponder=newTable;
    [newTable.fixturePaths setObject:[NSIndexPath indexPathForRow:0 inSection:0] forKey:moved.cell];
    moved.table=newTable; moved.cell.window=nil;
    [moved.cell prepareForReuse];
    CHECK_ID("reuse.table-change-restores-host",sameRect(moved.cell.frame,original));
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
    // Register while master disabled. Refresh must use only weakly registered cells.
    setting(@"enabled",@NO); WCKCornerScene *s=scene(NewMainFrameViewController.class,0,0);
    s.cell.frame=CGRectMake(0,100,420,60); layout(s); hostStyle(s,"refresh.off-original");
    drainRefresh();
    NSUInteger before=s.cell.fixtureLayoutCalls, needs=s.cell.fixtureNeedsLayoutCalls;
    setting(@"enabled",@YES); WCKRefreshCorners(); drainRefresh();
    CHECK_ID("refresh.registered",s.cell.fixtureNeedsLayoutCalls==needs+1 &&
        s.cell.fixtureLayoutCalls==before);
    layout(s);
    CHECK_ID("refresh.radius",near(s.cell.layer.cornerRadius,12));
    setting(@"globalCornerRadius",@18); before=s.cell.fixtureLayoutCalls; WCKRefreshCorners(); drainRefresh();
    layout(s);
    CHECK_ID("refresh.parameters",s.cell.fixtureLayoutCalls==before+1 && near(s.cell.layer.cornerRadius,18));
    setting(@"corners",@NO); WCKRefreshCorners(); drainRefresh(); layout(s); hostStyle(s,"refresh.off-restored");
}
static void lifetime(void) {
    __weak UITableViewCell *weakCell=nil;
    @autoreleasepool {
        WCKCornerScene *s=scene(NewMainFrameViewController.class,0,0);
        s.cell.frame=CGRectMake(0,100,420,60); layout(s); weakCell=s.cell;
        CHECK_ID("lifetime.alive",weakCell!=nil);
    }
    CHECK_ID("lifetime.weak",weakCell==nil); WCKRefreshCorners(); drainRefresh();
}
static void abi(void) {
    const char *frameArgs[]={@encode(CGRect)};
    CHECK_ID("abi.frame",WCKMethodMatches(UITableViewCell.class,@selector(setFrame:),@encode(void),frameArgs,1));
    CHECK_ID("hooks.nonempty",hookTargets.count>0);
    for (NSDictionary *entry in hookTargets) {
        NSString *c=entry[@"class"], *sel=entry[@"selector"];
        BOOL cellTarget=[@[@"MMTableViewCell",@"NewMainFrameCell"] containsObject:c];
        BOOL verifiedTarget=[@[@"MMHeadImageView", @"TLProfileImageView", @"FakeHeadImageView",
                              @"MMMsgContentNavBar", @"MMNewMsgContentNavBar", @"MMTabBar"] containsObject:c];
        BOOL viewTarget=[c isEqual:@"UIView"];
        BOOL allowedSelector=viewTarget
            ? ([sel isEqual:@"didMoveToWindow"] || [sel isEqual:@"setBackgroundColor:"] ||
               [sel isEqual:@"layoutSubviews"])
            : ([sel isEqual:@"setFrame:"] || [sel isEqual:@"layoutSubviews"] ||
               [sel isEqual:@"prepareForReuse"]);
        CHECK_ID("hooks.allowed-target",(cellTarget || verifiedTarget) && allowedSelector);
    }
}
int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK_ID("fixture.argument",argc==2); CHECK_ID("fixture.main-thread",NSThread.isMainThread);
        NSString *home=NSProcessInfo.processInfo.environment[@"HOME"];
        CHECK_ID("fixture.isolated-home",home.length>0 && [home.lastPathComponent hasPrefix:@"corners-"]);
        NSURL *file=[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Preferences/corners.plist"]];
        store=[[WCKSettings alloc] initWithFileURL:file];
        Method shared=class_getClassMethod(WCKSettings.class,@selector(shared));
        Method replacement=class_getClassMethod(WCKSettings.class,@selector(cornersFixtureShared));
        method_exchangeImplementations(shared,replacement);
        statuses=[NSMutableDictionary new]; hookTargets=[NSMutableArray new]; defaults(); WCKInstallCorners();
        CHECK_ID("install.ready",[statuses[@"corners"] isEqual:@"ready"]);
        NSString *which=[NSString stringWithUTF8String:argv[1]];
        if ([which isEqual:@"geometry"]) geometry();
        else if ([which isEqual:@"isolation"]) isolation();
        else if ([which isEqual:@"restore"]) restore();
        else if ([which isEqual:@"refresh"]) refresh();
        else if ([which isEqual:@"lifetime"]) lifetime();
        else if ([which isEqual:@"abi"]) abi();
        else CHECK_ID("fixture.known-case",NO);
        NSData *data=[NSJSONSerialization dataWithJSONObject:hookTargets options:0 error:NULL];
        printf("HOOK_TARGETS %s\n",[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String]);
        printf("CORNERS CASE %s PASS (%u checks)\n",argv[1],checks);
    } return 0;
}
