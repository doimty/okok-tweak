#import "WCKRuntime.h"

void WCKInstallVerifiedFeatures(void) {
    // Only runtime-validated implementations may become ready.
    WCKInstallReadAll();
    WCKInstallAlbumSheet();
    WCKInstallMomentsTime();
    WCKSetModuleStatus(@"noHotUpdate", @"热更新加载链待核验");
}
