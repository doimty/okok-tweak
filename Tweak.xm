#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// OKOK (com.chipsea.btWeigh) 3.7.54
// 1.0.3 证明 isVip 能让昵称变金色；会员卡片由 checkIfVip/refreshUI 单独控制。
// 这里不再猜 +0x39 的语义，直接在原逻辑之后纠正两个容器视图。

static void OKOKMark(NSString *name) {
    NSString *path = [@"/var/mobile/Library/Caches" stringByAppendingPathComponent:name];
    [[NSString stringWithFormat:@"%@ pid=%d", [NSDate date], getpid()]
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void OKOKApplyVipUI(id self) {
    @try {
        UIView *noVip = [self valueForKey:@"kNoVipContentView"];
        UIView *vip = [self valueForKey:@"kVipContentView"];
        UILabel *timeLab = [self valueForKey:@"kVipTimeLab"];
        if ([noVip isKindOfClass:[UIView class]]) {
            [noVip setHidden:YES];
        }
        if ([vip isKindOfClass:[UIView class]]) {
            [vip setHidden:NO];
        }
        if ([timeLab isKindOfClass:[UILabel class]]) {
            [timeLab setText:@"2099-12-31 到期"];
        }
    } @catch (NSException *e) {
    }
}

%ctor {
    OKOKMark(@"okok_tweak_loaded.txt");
}

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

- (void)checkIfVip {
    %orig;
    OKOKApplyVipUI(self);
}

- (void)refreshUI {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setIsVip:), YES);
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setVipExpirationTime:), @"2099-12-31");
    %orig;
    OKOKApplyVipUI(self);
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
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setIsVip:), YES);
    %orig;
}

%end
