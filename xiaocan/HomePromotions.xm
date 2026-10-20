#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import "XCHomePromotionPolicy.h"
#import "XCHomePromotionRegistry.h"

static Class gXCBottom, gXCCell, gXCTable, gXCScene;
static XCHomePromotionRegistry *gXCRegistry;

// Compare every runtime ABI component, not just selector availability or byte size.
static BOOL XCHomeABI(Class cls, const char *selector, const char *encoding) {
    Method method = class_getInstanceMethod(cls, sel_registerName(selector));
    if (!method) return NO;
    NSMethodSignature *actual = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    NSMethodSignature *expected = [NSMethodSignature signatureWithObjCTypes:encoding];
    if (!actual || actual.numberOfArguments != expected.numberOfArguments ||
        strcmp(actual.methodReturnType, expected.methodReturnType)) return NO;
    for (NSUInteger i = 0; i < actual.numberOfArguments; ++i)
        if (strcmp([actual getArgumentTypeAtIndex:i], [expected getArgumentTypeAtIndex:i])) return NO;
    return YES;
}
static BOOL XCExactTable(UITableView *table) {
    // The observed table is NSKVONotifying_xiaocan.HomeCategoryOuterTableView.
    return table && gXCTable && [table isKindOfClass:gXCTable];
}
static UITableView *XCContainingTable(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview)
        if ([v isKindOfClass:UITableView.class]) return (UITableView *)v;
    return nil;
}
static UITableViewCell *XCImageCell(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview)
        if ([v isKindOfClass:UITableViewCell.class])
            return object_getClass(v) == gXCCell ? (UITableViewCell *)v : nil;
    return nil;
}
static XCHomePromotionTableState *XCState(UITableView *table) {
    return NSThread.isMainThread && XCExactTable(table) ? [gXCRegistry stateForTable:table] : nil;
}
static void XCQueue(UITableView *table) {
    if (!XCState(table)) return;
    NSUInteger generation = [gXCRegistry queueTable:table];
    if (!generation) return;
    __weak UITableView *weakTable = table;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableView *liveTable = weakTable;
        if (!liveTable) return;
        BOOL available = liveTable.window && !liveTable.hasUncommittedUpdates &&
            object_getClass(liveTable.delegate) == gXCScene;
        if (![gXCRegistry beginReflowForTable:liveTable generation:generation available:available]) return;
        @try { [UIView performWithoutAnimation:^{ [liveTable beginUpdates]; [liveTable endUpdates]; }]; }
        @finally { [gXCRegistry stateForTable:liveTable].reflowing = NO; }
        XCQueue(liveTable); // Only dirty state can enqueue; no polling or layout-triggered retries.
    });
}
static void XCRestore(XCHomePromotionEntry *entry) {
    UITableViewCell *cell = entry.cell;
    if (cell && entry.applied) { cell.hidden = entry.hidden; cell.userInteractionEnabled = entry.interactive; }
}
static void XCForget(UITableViewCell *cell) {
    if (!NSThread.isMainThread) return;
    XCHomePromotionEntry *entry = [gXCRegistry forgetCell:cell];
    XCRestore(entry); XCQueue(entry.table);
}
static void XCInvalidate(UITableView *table) {
    if (XCState(table))
        for (XCHomePromotionEntry *entry in [gXCRegistry invalidateTable:table]) XCRestore(entry);
}
static void XCMark(UITableViewCell *cell) {
    UITableView *table = XCContainingTable(cell);
    if (table && (!XCExactTable(table) || object_getClass(table.delegate) != gXCScene)) { XCForget(cell); return; }
    XCHomePromotionEntry *old = [gXCRegistry entryForCell:cell];
    UITableView *oldTable = old.table;
    XCHomePromotionEntry *entry = [gXCRegistry markCell:cell table:table hidden:cell.hidden interactive:cell.userInteractionEnabled];
    if (table) {
        if (!entry.applied) { entry.hidden = cell.hidden; entry.interactive = cell.userInteractionEnabled; entry.applied = YES; }
        if (!cell.hidden) cell.hidden = YES;
        if (cell.userInteractionEnabled) cell.userInteractionEnabled = NO;
    }
    XCQueue(oldTable); XCQueue(table);
}

static char gXCMaterialKey;
static BOOL XCHasKnownMaterial(UIView *view, NSUInteger depth, NSUInteger *nodes) {
    if (depth > 12 || ++*nodes > 128) return NO;
    if ([view isKindOfClass:UIImageView.class]) {
        SEL getter = sel_registerName("sd_imageURL");
        if ([view respondsToSelector:getter]) {
            id live = ((id (*)(id, SEL))objc_msgSend)(view, getter);
            if (live) {
                if ([live isKindOfClass:NSURL.class] &&
                    XCHomePromotionShouldFilter(YES, YES, [(NSURL *)live absoluteString].UTF8String)) return YES;
                // A different live binding invalidates any earlier filtered material.
                objc_setAssociatedObject(view, &gXCMaterialKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
            } else {
                NSString *blocked = objc_getAssociatedObject(view, &gXCMaterialKey);
                if (XCHomePromotionShouldFilter(YES, YES, blocked.UTF8String)) return YES;
            }
        }
    }
    for (UIView *child in view.subviews)
        if (XCHasKnownMaterial(child, depth + 1, nodes)) return YES;
    return NO;
}
static void XCClearMaterialMarks(UIView *view, NSUInteger depth, NSUInteger *nodes) {
    if (depth > 12 || ++*nodes > 128) return;
    objc_setAssociatedObject(view, &gXCMaterialKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    for (UIView *child in view.subviews) XCClearMaterialMarks(child, depth + 1, nodes);
}
static void XCRefreshCell(UITableViewCell *cell) {
    if (!NSThread.isMainThread || object_getClass(cell) != gXCCell) return;
    NSUInteger nodes = 0;
    if (XCHasKnownMaterial(cell, 0, &nodes)) XCMark(cell);
    else XCForget(cell);
}

%group XCHomeBottom
%hook XCBottomBar
- (void)didMoveToWindow {
    %orig;
    if (object_getClass(self) == gXCBottom) { UIView *bar = (UIView *)self; bar.hidden = YES; bar.userInteractionEnabled = NO; }
}
- (void)setHidden:(BOOL)hidden { %orig(object_getClass(self) == gXCBottom ? YES : hidden); }
- (void)setUserInteractionEnabled:(BOOL)enabled { %orig(object_getClass(self) == gXCBottom ? NO : enabled); }
%end
%end

%group XCHomeMiddle
%hook UIImageView
- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder {
    if (!NSThread.isMainThread) { %orig; return; }
    UITableViewCell *cell = XCImageCell(self);
    if (!cell) { %orig; return; }
    const char *fullURL = [url isKindOfClass:NSURL.class] ? url.absoluteString.UTF8String : NULL;
    if (XCHomePromotionShouldFilter(gXCRegistry != nil, cell != nil, fullURL)) {
        objc_setAssociatedObject(self, &gXCMaterialKey, url.absoluteString, OBJC_ASSOCIATION_COPY_NONATOMIC);
        XCMark(cell); %orig(nil, nil); return;
    }
    objc_setAssociatedObject(self, &gXCMaterialKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    %orig;
    if (cell) XCRefreshCell(cell);
}
%end
%hook XCPicCell
- (void)prepareForReuse {
    NSUInteger nodes = 0; XCClearMaterialMarks((UIView *)self, 0, &nodes);
    XCForget((UITableViewCell *)self); %orig;
}
- (void)didMoveToWindow {
    %orig;
    if (!NSThread.isMainThread || object_getClass(self) != gXCCell) return;
    XCHomePromotionEntry *entry = [gXCRegistry entryForCell:self];
    if (entry.table && !XCContainingTable((UIView *)self)) XCForget((UITableViewCell *)self);
    else XCRefreshCell((UITableViewCell *)self);
}
- (void)layoutSubviews {
    %orig;
    XCRefreshCell((UITableViewCell *)self);
}
%end
%hook XCHomeScene
- (double)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    if (NSThread.isMainThread && object_getClass(self) == gXCScene && XCExactTable(table) &&
        table.delegate == (id)self && !XCState(table).depth && path) {
        UITableViewCell *cell = [table cellForRowAtIndexPath:path];
        if (object_getClass(cell) == gXCCell && [gXCRegistry isMarkedCell:cell table:table] &&
            [[table indexPathForCell:cell] isEqual:path]) return 0.01;
    }
    return %orig;
}
%end
%hook XCHomeTable
- (void)reloadData { XCInvalidate((UITableView *)self); %orig; }
- (void)reloadRowsAtIndexPaths:(NSArray *)paths withRowAnimation:(UITableViewRowAnimation)animation { XCInvalidate((UITableView *)self); %orig; }
- (void)insertRowsAtIndexPaths:(NSArray *)paths withRowAnimation:(UITableViewRowAnimation)animation { XCInvalidate((UITableView *)self); %orig; }
- (void)deleteRowsAtIndexPaths:(NSArray *)paths withRowAnimation:(UITableViewRowAnimation)animation { XCInvalidate((UITableView *)self); %orig; }
- (void)moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination { XCInvalidate((UITableView *)self); %orig; }
- (void)reloadSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation { XCInvalidate((UITableView *)self); %orig; }
- (void)insertSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation { XCInvalidate((UITableView *)self); %orig; }
- (void)deleteSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation { XCInvalidate((UITableView *)self); %orig; }
- (void)moveSection:(NSInteger)source toSection:(NSInteger)destination { XCInvalidate((UITableView *)self); %orig; }
- (void)beginUpdates {
    XCHomePromotionTableState *state = XCState((UITableView *)self);
    if (state && !state.reflowing) { XCInvalidate((UITableView *)self); ++state.depth; }
    %orig;
}
- (void)endUpdates {
    %orig;
    XCHomePromotionTableState *state = XCState((UITableView *)self);
    if (state && !state.reflowing) { if (state.depth) --state.depth; XCQueue((UITableView *)self); }
}
- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL))completion {
    XCHomePromotionTableState *state = XCState((UITableView *)self);
    if (!state || state.reflowing) { %orig; return; }
    XCInvalidate((UITableView *)self); ++state.depth;
    __weak UITableView *weakTable = (UITableView *)self;
    void (^wrappedCompletion)(BOOL) = ^(BOOL finished) {
        if (state.depth) --state.depth;
        if (completion) completion(finished);
        XCQueue(weakTable);
    };
    %orig(updates, wrappedCompletion);
}
%end
%end

%ctor {
    @autoreleasepool {
        NSBundle *app = NSBundle.mainBundle;
        if (!XCHomePromotionAppIsSupported(app.bundleIdentifier.UTF8String,
                [[app objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String])) return;
        gXCBottom = objc_getClass("_TtC7xiaocan19HomeBottomCenterBar");
        char boolSetter[] = { 'v', '@', ':', @encode(BOOL)[0], 0 };
        if ([gXCBottom isSubclassOfClass:UIView.class] &&
            XCHomeABI(gXCBottom, "didMoveToWindow", "v@:") &&
            XCHomeABI(gXCBottom, "setHidden:", boolSetter) &&
            XCHomeABI(gXCBottom, "setUserInteractionEnabled:", boolSetter)) {
            %init(XCHomeBottom, XCBottomBar = gXCBottom);
            NSLog(@"[XiaocanAdFree 1.0.9] home bottom hook ready");
        } else NSLog(@"[XiaocanAdFree 1.0.9] home bottom disabled: class/ABI mismatch");
        gXCCell = objc_getClass("_TtC7xiaocan12IndexPicCell");
        gXCTable = objc_getClass("_TtC7xiaocan26HomeCategoryOuterTableView");
        gXCScene = objc_getClass("_TtC7xiaocan9HomeScene");
        BOOL ready = [gXCCell isSubclassOfClass:UITableViewCell.class] &&
            [gXCTable isSubclassOfClass:UITableView.class] && [gXCScene isSubclassOfClass:UIViewController.class] &&
            XCHomeABI(UIImageView.class, "sd_setImageWithURL:placeholderImage:", "v@:@@") &&
            XCHomeABI(UIImageView.class, "sd_imageURL", "@@:") &&
            XCHomeABI(gXCCell, "layoutSubviews", "v@:") &&
            XCHomeABI(gXCCell, "prepareForReuse", "v@:") && XCHomeABI(gXCCell, "didMoveToWindow", "v@:") &&
            XCHomeABI(gXCScene, "tableView:heightForRowAtIndexPath:", "d@:@@");
        const char *plain[] = { "reloadData", "beginUpdates", "endUpdates" };
        for (unsigned i = 0; i < sizeof plain / sizeof plain[0]; ++i) ready &= XCHomeABI(gXCTable, plain[i], "v@:");
        const char *animated[] = { "reloadRowsAtIndexPaths:withRowAnimation:", "insertRowsAtIndexPaths:withRowAnimation:",
            "deleteRowsAtIndexPaths:withRowAnimation:", "reloadSections:withRowAnimation:",
            "insertSections:withRowAnimation:", "deleteSections:withRowAnimation:" };
        char animationABI[] = { 'v', '@', ':', '@', @encode(NSInteger)[0], 0 };
        for (unsigned i = 0; i < sizeof animated / sizeof animated[0]; ++i) ready &= XCHomeABI(gXCTable, animated[i], animationABI);
        char moveABI[] = { 'v', '@', ':', @encode(NSInteger)[0], @encode(NSInteger)[0], 0 };
        char boolGetter[] = { @encode(BOOL)[0], '@', ':', 0 };
        ready &= XCHomeABI(gXCTable, "moveRowAtIndexPath:toIndexPath:", "v@:@@") &&
            XCHomeABI(gXCTable, "moveSection:toSection:", moveABI) &&
            XCHomeABI(gXCTable, "performBatchUpdates:completion:", "v@:@?@?") &&
            XCHomeABI(gXCTable, "indexPathForCell:", "@@:@") &&
            XCHomeABI(gXCTable, "cellForRowAtIndexPath:", "@@:@") &&
            XCHomeABI(gXCTable, "hasUncommittedUpdates", boolGetter);
        if (ready) {
            gXCRegistry = [XCHomePromotionRegistry new];
            %init(XCHomeMiddle, XCPicCell = gXCCell, XCHomeTable = gXCTable, XCHomeScene = gXCScene);
            NSLog(@"[XiaocanAdFree 1.0.9] home middle hook ready, exact material only");
        } else NSLog(@"[XiaocanAdFree 1.0.9] home middle disabled: class/ABI mismatch");
    }
}
