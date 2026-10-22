#import <UIKit/UIKit.h>
#import "WCKSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// Generic second-level page: one switch, a short explanation, and optional
/// text settings. Used by features that only need a switch and a couple of
/// values, so the first-level list stays a list of entries.
@interface WCKFeatureDetailViewController : UITableViewController
- (instancetype)initWithSettings:(WCKSettings *)settings
                       featureID:(NSString *)featureID
                      settingsKey:(NSString *)key
                           title:(NSString *)title
                          detail:(NSString *)detail
                     extraRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)extraRows;
@end

NS_ASSUME_NONNULL_END
