#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL g_logicOverrideActive = NO;

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    if (g_logicOverrideActive) {
        return NO;
    }
    return orig_becomeFirstResponder(self, _cmd);
}

static void (*orig_makeKeyWindow)(id, SEL);
static void new_makeKeyWindow(id self, SEL _cmd) {
    if (g_logicOverrideActive) {
        return;
    }
    orig_makeKeyWindow(self, _cmd);
}

static void (*orig_becomeKeyWindow)(id, SEL);
static void new_becomeKeyWindow(id self, SEL _cmd) {
    if (g_logicOverrideActive) {
        return;
    }
    orig_becomeKeyWindow(self, _cmd);
}

static id (*orig_placementUndocked)(id, SEL, CGFloat);
static id new_placementUndocked(id self, SEL _cmd, CGFloat height) {
    if (g_logicOverrideActive) {
        return nil;
    }
    return orig_placementUndocked(self, _cmd, height);
}

static void performIronCladCleanup(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
        
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            NSString *name = NSStringFromClass([window class]);
            if ([name containsString:@"TextEffects"] || [name containsString:@"Keyboard"]) {
                window.hidden = YES;
                window.alpha = 0.0;
                for (UIView *subview in [window subviews]) {
                    NSString *subName = NSStringFromClass([subview class]);
                    if ([subName containsString:@"Dimming"] || [subName containsString:@"Shadow"] || [subName containsString:@"Corner"]) {
                        subview.hidden = YES;
                        [subview removeFromSuperview];
                    }
                }
            }
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
        
        Class windowClass = [UIWindow class];
        Method m2 = class_getInstanceMethod(windowClass, @selector(makeKeyWindow));
        if (m2) {
            orig_makeKeyWindow = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)new_makeKeyWindow);
        }
        
        Method m3 = class_getInstanceMethod(windowClass, @selector(becomeKeyWindow));
        if (m3) {
            orig_becomeKeyWindow = (void *)method_getImplementation(m3);
            method_setImplementation(m3, (IMP)new_becomeKeyWindow);
        }
        
        Class placementClass = objc_getClass("UIInputViewSetPlacementUndocked");
        if (placementClass) {
            Method m4 = class_getClassMethod(placementClass, objc_getSelector("placementWithUndockedHeight:"));
            if (m4) {
                orig_placementUndocked = (void *)method_getImplementation(m4);
                method_setImplementation(m4, (IMP)new_placementUndocked);
            }
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
    g_logicOverrideActive = YES;
    performIronCladCleanup();
    
    for (int i = 1; i <= 6; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            performIronCladCleanup();
        });
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g_logicOverrideActive = NO;
    });
}

@end
