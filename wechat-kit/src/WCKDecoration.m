#import "WCKDecoration.h"
#import "WCKRuntime.h"
#import "WCKSettings.h"
#import <math.h>

// Own tag, deliberately different from any tag observed in a sample.
// viewWithTag: is the only cleanup mechanism: a cell that stops qualifying
// must have exactly this view removed, never a host view.
const NSInteger WCKDecorationViewTag = 0x57434B44; // 'WCKD'
static NSMutableDictionary<NSString *, UIImage *> *sDecorationCache;

NSString *WCKDecorationPageDigitForOwnerName(NSString *ownerName) {
    if (!ownerName.length) return nil;
    // Fragment matching, same rationale as the corners page keys: the exact
    // owner class name varies between WeChat builds.
    if ([ownerName containsString:@"MainFrame"]) return @"1";
    if ([ownerName containsString:@"Contacts"]) return @"2";
    if ([ownerName containsString:@"FindFriend"] || [ownerName containsString:@"Discover"]) return @"3";
    if ([ownerName containsString:@"MoreViewController"]) return @"4";
    if ([ownerName containsString:@"WCPlugins"]) return @"5";
    return nil;
}

BOOL WCKDecorationPageVisible(NSString *visiblePages, NSString *digit) {
    if (!digit.length) return NO;
    if (!visiblePages.length) return YES; // Missing/empty means the default, all pages.
    return [visiblePages containsString:digit];
}

NSArray<NSString *> *WCKDecorationCandidateNames(BOOL dark) {
    // Highest resolution first: a @3x file wins over @2x/@1x, and a dark-only
    // folder never falls back to a light image (or vice versa).
    NSString *theme = dark ? @"深色" : @"浅色";
    return @[[theme stringByAppendingString:@"@3x.png"],
             [theme stringByAppendingString:@"@2x.png"],
             [theme stringByAppendingString:@"@1x.png"]];
}

static UITableView *WCKDecorationTable(UITableViewCell *cell) {
    UIView *parent = cell.superview;
    for (NSUInteger depth = 0; parent && depth < 24; ++depth, parent = parent.superview)
        if ([parent isKindOfClass:UITableView.class]) return (UITableView *)parent;
    return nil;
}

static UIViewController *WCKDecorationOwner(UITableView *table) {
    UIResponder *next = table;
    for (NSUInteger depth = 0; next && depth < 64; ++depth, next = next.nextResponder)
        if ([next isKindOfClass:UIViewController.class]) return (UIViewController *)next;
    return nil;
}

static double WCKDecorationNumber(NSDictionary *snapshot, NSString *key, double fallback,
                                  double low, double high) {
    id value = snapshot[key];
    double x = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    return isfinite(x) ? MIN(high, MAX(low, x)) : fallback;
}

// Cached by absolute path, invalidated on any settings write. Misses are not
// cached: a file added to the folder later must appear on the next layout.
// Only the first existing candidate is ever read from disk.
static UIImage *WCKDecorationImage(NSString *folder, BOOL dark) {
    if (!sDecorationCache) sDecorationCache = [NSMutableDictionary dictionary];
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *name in WCKDecorationCandidateNames(dark)) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        UIImage *cached = sDecorationCache[path];
        if (cached) return cached;
        if (![files fileExistsAtPath:path]) continue;
        UIImage *loaded = [UIImage imageWithContentsOfFile:path];
        if (!loaded || loaded.size.width <= 0 || loaded.size.height <= 0) continue;
        // Bake the file orientation in once, so layout never re-applies it.
        UIImage *fixed = loaded.imageOrientation == UIImageOrientationUp ? loaded :
            [UIImage imageWithCGImage:loaded.CGImage scale:1 orientation:UIImageOrientationUp];
        if (fixed) sDecorationCache[path] = fixed;
        return fixed;
    }
    return nil;
}

void WCKDecorationRemoveFromCell(UITableViewCell *cell) {
    if (!cell || !NSThread.isMainThread) return;
    @try {
        UIView *old = [cell viewWithTag:WCKDecorationViewTag];
        [old removeFromSuperview];
    } @catch (__unused NSException *exception) { /* Removal never breaks layout. */ }
}

void WCKDecorationApplyToCell(UITableViewCell *cell) {
    if (!cell || !NSThread.isMainThread) return;
    @try {
        NSDictionary *snapshot = WCKSettings.shared.snapshot;
        // Independent of the corners switch: master + this feature's switch.
        if (![snapshot[@"enabled"] boolValue] || ![snapshot[@"decorationEnabled"] boolValue]) {
            WCKDecorationRemoveFromCell(cell);
            return;
        }
        NSString *folder = snapshot[@"decorationFolder"];
        if (![folder isKindOfClass:NSString.class] || !folder.length) {
            WCKDecorationRemoveFromCell(cell);
            return;
        }
        folder = [folder stringByExpandingTildeInPath];
        UITableView *table = WCKDecorationTable(cell);
        NSString *digit = WCKDecorationPageDigitForOwnerName(
            NSStringFromClass(WCKDecorationOwner(table).class));
        NSString *visible = snapshot[@"decorationVisiblePages"];
        // A non-string stored value is a schema violation, not a page list;
        // a missing value means the default (all pages).
        if (!digit || (visible != nil && ![visible isKindOfClass:NSString.class])) {
            WCKDecorationRemoveFromCell(cell);
            return;
        }
        if (!WCKDecorationPageVisible([visible isKindOfClass:NSString.class] ? visible : nil, digit)) {
            WCKDecorationRemoveFromCell(cell);
            return;
        }
        if (cell.bounds.size.width <= 0 || cell.bounds.size.height <= 0) {
            WCKDecorationRemoveFromCell(cell);
            return;
        }
        BOOL dark = NO;
        @try { dark = cell.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark; }
        @catch (__unused NSException *exception) { dark = NO; }
        UIImage *image = WCKDecorationImage(folder, dark);
        if (!image) {
            WCKDecorationRemoveFromCell(cell);
            return;
        }
        double offsetX = WCKDecorationNumber(snapshot, @"decorationOffsetX", 0, -200, 200);
        double scale = WCKDecorationNumber(snapshot, @"decorationScale", 1, 0.5, 2);
        UIImageView *view = (UIImageView *)[cell viewWithTag:WCKDecorationViewTag];
        if (![view isKindOfClass:UIImageView.class]) {
            [view removeFromSuperview];
            view = [[UIImageView alloc] initWithImage:image];
            view.tag = WCKDecorationViewTag;
            view.contentMode = UIViewContentModeScaleAspectFill;
            view.clipsToBounds = YES;
            // Above the cell background, behind the content: inserting at
            // index 0 could hide the image behind a host background view.
            if (cell.backgroundView) [cell insertSubview:view aboveSubview:cell.backgroundView];
            else [cell insertSubview:view atIndex:0];
        } else {
            view.image = image;
        }
        // Assignment, never multiplication: a second layout on the same cell
        // must leave exactly the same geometry, not a twice-scaled image.
        view.transform = CGAffineTransformIdentity;
        view.frame = cell.bounds;
        view.center = CGPointMake(CGRectGetMidX(cell.bounds) + offsetX,
                                  CGRectGetMidY(cell.bounds));
        view.transform = CGAffineTransformMakeScale(scale, scale);
    } @catch (__unused NSException *exception) {
        WCKSetModuleStatus(@"decoration.debug.last", @"装饰图应用异常；保留宿主布局");
    }
}

void WCKDecorationInvalidateCache(void) {
    [sDecorationCache removeAllObjects];
}
