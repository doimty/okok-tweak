#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// 仅处理已在小蚕 3.21.6 真机验证的 GDT 开屏路径。
// 跳过实际展示，同时通知广告 delegate 开屏关闭，让 App 继续启动。
%hook GDTSplashAd

- (void)showAdInWindow:(UIWindow *)window
        withBottomView:(UIView *)bottomView
              skipView:(UIView *)skipView {
    SEL delegateSelector = sel_registerName("delegate");
    SEL closedSelector = sel_registerName("splashAdClosed:");

    id ad = (id)self;
    id delegate = nil;
    if ([ad respondsToSelector:delegateSelector]) {
        delegate = ((id (*)(id, SEL))objc_msgSend)(ad, delegateSelector);
    }

    if (delegate && [delegate respondsToSelector:closedSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(delegate, closedSelector, ad);
        return;
    }

    // SDK/版本行为不匹配时保留原广告展示，避免卡住启动流程。
    %orig;
}

%end
