#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// OKOK (com.chipsea.btWeigh) 3.7.54
// 会员状态：isVip + 到期时间，覆盖“我的”页与会员页。

#pragma mark - 会员业务层

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

%hook AppPayManager

- (BOOL)verifyVip {
    return YES;
}

%end

#pragma mark - 我的页面

%hook OKOKKYMyViewController2

- (BOOL)isVip {
    return YES;
}

- (NSString *)vipExpirationTime {
    return @"2099-12-31";
}

- (void)refreshUI {
    [self setIsVip:YES];
    [self setVipExpirationTime:@"2099-12-31"];
    %orig;
}

%end

#pragma mark - 会员页

%hook OKKYVIPVC

- (BOOL)isVip {
    return YES;
}

- (NSString *)expirationTime {
    return @"2099-12-31";
}

- (void)updateDataView {
    [self setIsVip:YES];
    %orig;
}

%end
