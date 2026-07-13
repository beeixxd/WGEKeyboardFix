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
        id window = nil;
        
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
            Class tfClass = NSClassFromString(@"UITextField");
            if (!tfClass) return;
            
            id shadowGuardField = [[tfClass alloc] init];
            if (!shadowGuardField) return;
            
            if ([window respondsToSelector:@selector(addSubview:)]) {
                [window performSelector:@selector(addSubview:) withObject:shadowGuardField];
            }
            
            if ([shadowGuardField respondsToSelector:@selector(becomeFirstResponder)]) {
                [shadowGuardField performSelector:@selector(becomeFirstResponder)];
            }
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([shadowGuardField respondsToSelector:@selector(resignFirstResponder)]) {
                    [shadowGuardField performSelector:@selector(resignFirstResponder)];
                }
                if ([shadowGuardField respondsToSelector:@selector(removeFromSuperview)]) {
                    [shadowGuardField performSelector:@selector(removeFromSuperview)];
                }
            });
        }
    });
}

@end
