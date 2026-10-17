#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

// OKOK (com.chipsea.btWeigh) 3.7.54
// “我的”页 refreshUI/checkIfVip 读取的是 +0x39 的 BOOL，不是 isVip 的 +0x8。
// 这里直接写该 ivar，再走原逻辑。

static void OKOKMark(NSString *name) {
    NSString *path = [@"/var/mobile/Library/Caches" stringByAppendingPathComponent:name];
    [[NSString stringWithFormat:@"%@ pid=%d", [NSDate date], getpid()]
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
    OKOKMark(@"okok_checkifvip.txt");
    *(BOOL *)((char *)self + 0x39) = YES;
    %orig;
}

- (void)refreshUI {
    OKOKMark(@"okok_refreshui.txt");
    *(BOOL *)((char *)self + 0x39) = YES;
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setVipExpirationTime:), @"2099-12-31");
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
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setIsVip:), YES);
    %orig;
}

%end
