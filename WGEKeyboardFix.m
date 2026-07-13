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
        UIWindow *activeWindow = [UIApplication sharedApplication].keyWindow;
        if (!activeWindow) {
            NSArray *windows = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) {
                        windows = [((UIWindowScene *)scene) windows];
                        break;
                    }
                }
            }
            if (!windows || windows.count == 0) {
                windows = [UIApplication sharedApplication].windows;
            }
            for (UIWindow *w in windows) {
                if (w.isKeyWindow) {
                    activeWindow = w;
                    break;
                }
            }
            if (!activeWindow && windows.count > 0) {
                activeWindow = windows.firstObject;
            }
        }
        
        if (activeWindow) {
            UITextField *shadowGuardField = [[UITextField alloc] initWithFrame:CGRectZero];
            shadowGuardField.hidden = YES;
            [activeWindow addSubview:shadowGuardField];
            
            [shadowGuardField becomeFirstResponder];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [shadowGuardField resignFirstResponder];
                [shadowGuardField removeFromSuperview];
            });
        }
    });
}

@end
