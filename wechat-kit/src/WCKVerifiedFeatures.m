#import "WCKRuntime.h"

void WCKInstallVerifiedFeatures(void) {
    // Only runtime-validated implementations may become ready.
    WCKInstallReadAll();
    WCKSetModuleStatus(@"albumSheet", @"已定位相册配置键；注册接口待核验");
    WCKSetModuleStatus(@"momentsTime", @"时间字段与布局待核验");
    WCKSetModuleStatus(@"noHotUpdate", @"热更新加载链待核验");
}
