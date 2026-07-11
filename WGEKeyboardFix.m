#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static void forceDismissKeyboard(void) {
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

@interface WGEKeyboardObserver : NSObject
@end

@implementation WGEKeyboardObserver

+ (void)load {
    static WGEKeyboardObserver *observer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        observer = [[WGEKeyboardObserver alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:observer
                                                 selector:@selector(handleAppActive)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] addObserver:observer
                                                 selector:@selector(handleAppActive)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    });
}

- (void)handleAppActive {
    forceDismissKeyboard();
    for (int i = 1; i <= 4; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            forceDismissKeyboard();
        });
    }
}

@end
