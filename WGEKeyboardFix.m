#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>

static void syncAppKeyboardState() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (!keyWindow && [[UIApplication sharedApplication] windows].count > 0) {
            keyWindow = [[UIApplication sharedApplication] windows] firstObject;
        }
        
        if (keyWindow) {
            [keyWindow endEditing:YES];
        }
        
        Class keyboardClass = objc_getClass("UIKeyboardImpl");
        if (keyboardClass) {
            id sharedImpl = [keyboardClass performSelector:@selector(sharedInstance)];
            if (sharedImpl) {
                if ([sharedImpl respondsToSelector:@selector(dismissKeyboard)]) {
                    [sharedImpl performSelector:@selector(dismissKeyboard)];
                }
                if ([sharedImpl respondsToSelector:@selector(orderOutWithTrackedView:Duration:Notify:)]) {
                    [sharedImpl performSelector:@selector(orderOutWithTrackedView:Duration:Notify:) withObject:nil withObject:@(0.0) withObject:@(NO)];
                }
                if ([sharedImpl respondsToSelector:@selector(setInitialFrameWithConfig:)]) {
                    [sharedImpl performSelector:@selector(minimize)];
                }
            }
        }
        
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            NSString *windowName = NSStringFromClass([window class]);
            if ([windowName containsString:@"TextEffectsWindow"] || [windowName containsString:@"Keyboard"]) {
                window.hidden = YES;
                window.alpha = 0.0;
                for (UIView *subview in [window subviews]) {
                    NSString *subName = NSStringFromClass([subview class]);
                    if ([subName containsString:@"Dimming"] || [subName containsString:@"Shadow"]) {
                        subview.hidden = YES;
                        [subview removeFromSuperview];
                    }
                }
            }
        }
    });
}

__attribute__((constructor)) static void init() {
    int token;
    notify_register_dispatch("com.apple.springboard.lockstate", &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state;
        notify_get_state(t, &state);
        if (state == 0) {
            for (int i = 1; i <= 4; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    syncAppKeyboardState();
                });
            }
        }
    });
}
