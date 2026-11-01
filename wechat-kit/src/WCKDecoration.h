#import <UIKit/UIKit.h>

// List decoration images: an independent WCK feature, written from the
// behaviour observed in a third-party sample, not from its code. It draws one
// user-chosen image at the back of a list cell on five named pages. It owns
// no hook of its own: the existing cell layout path calls the apply/remove
// entry points, so it can never double-hook UITableViewCell layoutSubviews
// alongside the corners module.
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT const NSInteger WCKDecorationViewTag;
// Page digits, in WCK order: 1 home sessions, 2 contacts, 3 discover,
// 4 "me" page, 5 plugin pages. An empty visible-pages string means "all".
FOUNDATION_EXPORT NSString * _Nullable WCKDecorationPageDigitForOwnerName(NSString * _Nullable ownerName);
FOUNDATION_EXPORT BOOL WCKDecorationPageVisible(NSString * _Nullable visiblePages, NSString *digit);
FOUNDATION_EXPORT NSArray<NSString *> *WCKDecorationCandidateNames(BOOL dark);
FOUNDATION_EXPORT void WCKDecorationApplyToCell(UITableViewCell *cell);
FOUNDATION_EXPORT void WCKDecorationRemoveFromCell(UITableViewCell *cell);
FOUNDATION_EXPORT void WCKDecorationInvalidateCache(void);
NS_ASSUME_NONNULL_END
