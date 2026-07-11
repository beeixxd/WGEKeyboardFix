#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL g_appJustBecameActive = NO;

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    if (g_appJustBecameActive) {
        UIEvent *currentEvent = nil;
        id UIApplicationClass = objc_getClass("UIApplication");
        if (UIApplicationClass) {
            id sharedApp = [UIApplicationClass performSelector:@selector(sharedInstance)];
            if (sharedApp && [sharedApp respondsToSelector:@selector(currentEvent)]) {
                currentEvent = [sharedApp performSelector:@selector(currentEvent)];
            }
        }
        
        if (!currentEvent || currentEvent.type != UIEventTypeTouches) {
            return NO;
        }
    }
    return orig_becomeFirstResponder(self, _cmd);
}

static void forceDismissKeyboard(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        NSArray *windows = [[UIApplication sharedApplication] windows];
        for (UIWindow *window in windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (!keyWindow && windows.count > 0) {
            keyWindow = [windows firstObject];
        }
        if (keyWindow) {
            [keyWindow endEditing:YES];
        }
    });
}

@interface WGEKeyboardOverrideObserver : NSObject
@end

@implementation WGEKeyboardOverrideObserver

+ (void)load {
    static WGEKeyboardOverrideObserver *observer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        observer = [[WGEKeyboardOverrideObserver alloc] init];
        
        Class viewClass = [UIView class];
        Method m1 = class_getInstanceMethod(viewClass, @selector(becomeFirstResponder));
        if (m1) {
            orig_becomeFirstResponder = (void *)method_getImplementation(m1);
            method_setImplementation(m1, (IMP)new_becomeFirstResponder);
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:observer
                                                 selector:@selector(triggerOverrideMode)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] addObserver:observer
                                                 selector:@selector(triggerOverrideMode)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    });
}

- (void)triggerOverrideMode {
    g_appJustBecameActive = YES;
    forceDismissKeyboard();
    
    for (int i = 1; i <= 4; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            forceDismissKeyboard();
        });
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_appJustBecameActive = NO;
    });
}

@end
