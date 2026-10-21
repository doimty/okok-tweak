#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Use the actual main bundle's on-disk identity, never its mutable display metadata.
// readable is NO for transient I/O/parse failures; callers must not cache those failures.
FOUNDATION_EXPORT BOOL WCKHostMatchesBundle(NSBundle *bundle, BOOL *readable);
NS_ASSUME_NONNULL_END
