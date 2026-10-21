#import "WCKRuntime.h"

// Original reference installer targets ExptService -getExpt:withBoolDef:,
// not NewABTestMgr or MMConfigMgr. Only this exact display experiment is changed.
static BOOL (*sOriginalAlbumExpt)(id, SEL, id, BOOL);
static BOOL WCKAlbumExpt(id service, SEL cmd, id key, BOOL fallback) {
    if ([key isKindOfClass:NSString.class] &&
        [key isEqualToString:@"clicfg_chat_album_pagesheet_mode"] && WCKEnabled(@"albumSheet"))
        return YES;
    return sOriginalAlbumExpt(service, cmd, key, fallback);
}

void WCKInstallAlbumSheet(void) {
    const char *args[] = {"@", @encode(BOOL)};
    BOOL ready = WCKInstallHook(NSClassFromString(@"ExptService"),
        NSSelectorFromString(@"getExpt:withBoolDef:"), (IMP)WCKAlbumExpt,
        (IMP *)&sOriginalAlbumExpt, @encode(BOOL), args, 2);
    WCKSetModuleStatus(@"albumSheet", ready && sOriginalAlbumExpt ? @"ready" : @"相册实验 ABI 或 hook 不可用");
}
