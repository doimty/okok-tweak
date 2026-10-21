#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "WCKRuntime.h"
#import "WCKSettings.h"

@interface WCKMomentsTimeState : NSObject
@property(nonatomic, weak) UIView *cell;
@property(nonatomic, weak) UILabel *label;
@property(nonatomic, weak) id item;
@property(nonatomic, copy) NSString *originalText;
@property(nonatomic, copy) NSString *appliedText;
@end
@implementation WCKMomentsTimeState @end
static char sMomentsStateKey;
static NSHashTable<UIView *> *sMomentsCells;
static void (*sMomentsUpdate)(id, SEL, id, id);
static void (*sMomentsAdjust)(id, SEL);
static _Thread_local NSUInteger sMomentsDepth;

static NSString *WCKMomentsFormat(unsigned int stamp) {
    if (!stamp) return nil;
    NSString *format = [WCKSettings.shared stringForKey:@"momentsFormat" defaultValue:@"yyyy-MM-dd HH:mm:ss"];
    if (!format.length || format.length > 128) return nil;
    @try {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        formatter.timeZone = NSTimeZone.localTimeZone; formatter.dateFormat = format;
        NSString *text = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
        return text.length && text.length <= 256 ? text : nil;
    } @catch (__unused NSException *exception) { return nil; }
}
static void WCKMomentsRestore(WCKMomentsTimeState *state) {
    if (state.appliedText && [state.label.text isEqualToString:state.appliedText])
        state.label.text = state.originalText;
    state.appliedText = nil;
}
static void WCKMomentsApply(UIView *cell) {
    if (!NSThread.isMainThread || sMomentsDepth) return;
    @try {
        WCKMomentsTimeState *state = objc_getAssociatedObject(cell, &sMomentsStateKey);
        id item = ((id (*)(id,SEL))objc_msgSend)(cell, NSSelectorFromString(@"m_dataItem"));
        id label = ((id (*)(id,SEL))objc_msgSend)(cell, NSSelectorFromString(@"m_timeLabel"));
        if (![label isKindOfClass:UILabel.class] || !item) { WCKMomentsRestore(state); return; }
        if (!state) {
            state = [WCKMomentsTimeState new]; state.cell = cell;
            objc_setAssociatedObject(cell, &sMomentsStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [sMomentsCells addObject:cell];
        }
        if (state.label != label || state.item != item) {
            WCKMomentsRestore(state); state.label = label; state.item = item;
            state.originalText = [label text];
        } else if (!state.appliedText || ![state.appliedText isEqualToString:[label text]]) {
            state.originalText = [label text]; state.appliedText = nil;
        }
        if (!WCKEnabled(@"momentsTime") ||
            !WCKMethodMatches(object_getClass(item), NSSelectorFromString(@"createtime"), "I", NULL, 0)) {
            WCKMomentsRestore(state); return;
        }
        unsigned int stamp = ((unsigned int (*)(id,SEL))objc_msgSend)(item, NSSelectorFromString(@"createtime"));
        NSString *text = WCKMomentsFormat(stamp);
        if (!text) { WCKMomentsRestore(state); return; }
        state.appliedText = text; [(UILabel *)label setText:text];
    } @catch (__unused NSException *exception) { }
}
static void WCKMomentsUpdated(id cell, SEL cmd, id item, id area) {
    WCKMomentsRestore(objc_getAssociatedObject(cell, &sMomentsStateKey));
    sMomentsUpdate(cell, cmd, item, area);
    WCKMomentsApply(cell);
    // Let the host recompute available time/location/source width; no guessed frames.
    if (sMomentsAdjust) {
        ++sMomentsDepth;
        @try { sMomentsAdjust(cell, NSSelectorFromString(@"adjustTimeLabelLine")); }
        @finally { --sMomentsDepth; }
    }
}
static void WCKMomentsAdjusted(id cell, SEL cmd) {
    WCKMomentsApply(cell); sMomentsAdjust(cell, cmd);
}
void WCKInstallMomentsTime(void) {
    Class cls = NSClassFromString(@"WCTimeLineCellView");
    if (!WCKMethodMatches(cls, NSSelectorFromString(@"m_dataItem"), "@", NULL, 0) ||
        !WCKMethodMatches(cls, NSSelectorFromString(@"m_timeLabel"), "@", NULL, 0) ||
        !WCKMethodMatches(NSClassFromString(@"WCDataItem"), NSSelectorFromString(@"createtime"), "I", NULL, 0)) {
        WCKSetModuleStatus(@"momentsTime", @"朋友圈数据或时间字段 ABI 不可用"); return;
    }
    sMomentsCells = [NSHashTable weakObjectsHashTable];
    const char *args[] = {"@", "@"};
    BOOL update = WCKInstallHook(cls, NSSelectorFromString(@"updateWithDataItem:actionAreaVM:"),
        (IMP)WCKMomentsUpdated, (IMP *)&sMomentsUpdate, "v", args, 2);
    BOOL adjust = WCKInstallHook(cls, NSSelectorFromString(@"adjustTimeLabelLine"),
        (IMP)WCKMomentsAdjusted, (IMP *)&sMomentsAdjust, "v", NULL, 0);
    BOOL ready = update && adjust && sMomentsUpdate && sMomentsAdjust;
    WCKSetModuleStatus(@"momentsTime", ready ? @"ready" : @"朋友圈更新或布局 hook 不可用");
    if (ready) [NSNotificationCenter.defaultCenter addObserverForName:WCKSettingsDidChangeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            for (UIView *cell in sMomentsCells.allObjects) {
                WCKMomentsApply(cell); ++sMomentsDepth;
                @try { sMomentsAdjust(cell, NSSelectorFromString(@"adjustTimeLabelLine")); }
                @finally { --sMomentsDepth; }
            }
        }];
}
