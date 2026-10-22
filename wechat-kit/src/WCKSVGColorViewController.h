#import <UIKit/UIKit.h>
#import "WCKSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// Second-level page for SVG colouring: fixed light/dark pair or a palette,
/// plus the icon include/exclude lists. Purely local UI over WCKSettings.
@interface WCKSVGColorViewController : UITableViewController
- (instancetype)initWithSettings:(WCKSettings *)settings;
@end

NS_ASSUME_NONNULL_END
