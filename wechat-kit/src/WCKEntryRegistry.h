#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Optional WCPluginsMgr integration. Main-thread only; idempotent and retryable.
FOUNDATION_EXPORT BOOL WCKRegisterPluginEntry(void);
NS_ASSUME_NONNULL_END
