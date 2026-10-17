#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// OKOK (com.chipsea.btWeigh) 3.7.54
// 第一步只验证会员 hook 不影响启动；广告 hook 随后分组加入。

#pragma mark - 会员状态

%hook VIPBusiness

- (BOOL)isVip {
    return YES;
}

%end

%hook ScaleAccessBusiness

- (BOOL)isVip {
    return YES;
}

%end

%hook OKKYVIPVC

- (BOOL)isVip {
    return YES;
}

%end

%hook OKOKKYMyViewController2

- (BOOL)isVip {
    return YES;
}

%end

%hook AppPayManager

- (BOOL)verifyVip {
    return YES;
}

%end
