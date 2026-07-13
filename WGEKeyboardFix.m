#import <UIKit/UIKit.h>

@interface WGEKeyboardUltimatePerfectFixer : NSObject
@end

@implementation WGEKeyboardUltimatePerfectFixer

+ (void)load {
    static WGEKeyboardUltimatePerfectFixer *fixer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fixer = [[WGEKeyboardUltimatePerfectFixer alloc] init];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
        });
    });
}

- (void)onAppUnlockSuccess {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        UIWindow *window = nil;
        if ([app respondsToSelector:@selector(keyWindow)]) {
            window = [app performSelector:@selector(keyWindow)];
        }
        if (!window && [app respondsToSelector:@selector(windows)]) {
            NSArray *allWindows = [app performSelector:@selector(windows)];
            if (allWindows && allWindows.count > 0) {
                window = allWindows.firstObject;
            }
        }
        if (window) {
            UITextField *shadowGuardField = [[UITextField alloc] initWithFrame:CGRectZero];
            [window addSubview:shadowGuardField];
            [shadowGuardField becomeFirstResponder];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [shadowGuardField resignFirstResponder];
                [shadowGuardField removeFromSuperview];
            });
        }
    });
}

@end
