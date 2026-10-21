#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const WCKSettingsDidChangeNotification;

@interface WCKSettings : NSObject
+ (instancetype)shared;
- (BOOL)boolForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)fallback;
// Main-thread only. A failed write leaves the snapshot unchanged and sends no notification.
- (BOOL)setObject:(id)value forKey:(NSString *)key error:(NSError * _Nullable * _Nullable)error;
- (NSDictionary<NSString *, id> *)snapshot;
@end

NS_ASSUME_NONNULL_END
