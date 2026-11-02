#import <UIKit/UIKit.h>
#import "WCKSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// Generic second-level page: one switch, a short explanation, and optional
/// text settings. Used by features that only need a switch and a couple of
/// values, so the first-level list stays a list of entries.
/// The header card mirrors the first-level hero: an icon tile, the feature
/// title and a one-line status. Set heroIconName/heroTintColor before the
/// view loads; when unset, no header card is shown.
@interface WCKFeatureDetailViewController : UITableViewController
@property (nonatomic, copy, nullable) NSString *heroIconName;
@property (nonatomic, strong, nullable) UIColor *heroTintColor;
- (instancetype)initWithSettings:(WCKSettings *)settings
                       featureID:(NSString *)featureID
                      settingsKey:(NSString *)key
                           title:(NSString *)title
                          detail:(NSString *)detail
                     extraRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)extraRows;
@end

NS_ASSUME_NONNULL_END
