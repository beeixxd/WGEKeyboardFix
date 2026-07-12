#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gWGEAppTransitionActive = NO;
static BOOL gWGEUserIsInteracting = NO;
static BOOL gWGEAppIsLockedState = NO;
static BOOL gWGEIsAppLockScreenShowing = YES;

static NSArray<UIWindow *> *WGEAllWindows(void) {
    NSMutableArray<UIWindow *> *result = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w) [result addObject:w];
            }
        }
    }
    if (result.count == 0) {
        NSArray *legacyWindows = [UIApplication sharedApplication].windows;
        if (legacyWindows) [result addObjectsFromArray:legacyWindows];
    }
    return result;
}

static void WGERunFullCleanup(void) {
    if (gWGEAppIsLockedState) {
        return;
    }
    
    // 只要不是在解锁页，就全局无死角注销第一响应者（光标）
    if (!gWGEIsAppLockScreenShowing) {
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    }

    for (UIWindow *w in WGEAllWindows()) {
        NSString *windowClassName = NSStringFromClass([w class]);
        
        if ([windowClassName rangeOfString:@"Passcode"].location != NSNotFound ||
            [windowClassName rangeOfString:@"Secure"].location != NSNotFound) {
            continue;
        }

        // 如果已经成功进入首页
        if (!gWGEIsAppLockScreenShowing) {
            if ([windowClassName containsString:@"TextEffects"] || [windowClassName containsString:@"Keyboard"]) {
                // 不只是改frame，直接把整个键盘载体窗口的隐藏和透明度锁死，从根源断绝任何阴影图层的渲染空间
                w.hidden = YES;
                w.alpha = 0.0;
                CGRect frame = w.frame;
                frame.size.height = 0;
                w.frame = frame;
            }
        } else {
            // 如果在解锁页，且当前并没有真正弹起键盘（高度很小或为0），说明这是卡死的残影窗口，将其隐形
            if (([windowClassName containsString:@"TextEffects"] || [windowClassName containsString:@"Keyboard"]) && w.frame.size.height < 100) {
                w.alpha = 0.0;
            }
        }

        // 针对图层级别的特殊清理
        for (UIView *subview in [w subviews]) {
            NSString *subName = NSStringFromClass([subview class]);
            if ([subName containsString:@"Dimming"] || 
                [subName containsString:@"Shadow"] || 
                [subName containsString:@"Corner"] ||
                [subName containsString:@"Keyboard"]) { // 把带有Keyboard关键字的非Window子视图也纳入消杀
                
                if (!gWGEIsAppLockScreenShowing) {
                    subview.hidden = YES;
                    subview.alpha = 0.0;
                    CGRect frame = subview.frame;
                    frame.size.height = 0;
                    subview.frame = frame;
                    [subview removeFromSuperview];
                }
            }
        }
    }
}

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    if (gWGEIsAppLockScreenShowing) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    if (gWGEAppIsLockedState || gWGEAppTransitionActive) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    if (!gWGEUserIsInteracting) {
        WGERunFullCleanup();
        return NO;
    }
    
    return orig_becomeFirstResponder(self, _cmd);
}

static void (*orig_windowSendEvent)(id, SEL, UIEvent *);
static void new_windowSendEvent(id self, SEL _cmd, UIEvent *event) {
    if (event && event.type == UIEventTypeTouches) {
        gWGEUserIsInteracting = YES;
    }
    orig_windowSendEvent(self, _cmd, event);
    if (event && event.type == UIEventTypeTouches) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gWGEUserIsInteracting = NO;
        });
    }
}

static void (*orig_viewWillDisappear)(id, SEL, BOOL);
static void new_viewWillDisappear(id self, SEL _cmd, BOOL animated) {
    orig_viewWillDisappear(self, _cmd, animated);
    WGERunFullCleanup();
}

@interface WGEKeyboardUltimatePerfectFixer : NSObject
@end

@implementation WGEKeyboardUltimatePerfectFixer

+ (void)load {
    static WGEKeyboardUltimatePerfectFixer *fixer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fixer = [[WGEKeyboardUltimatePerfectFixer alloc] init];
        
        Class viewClass = [UIView class];
        Method m1 = class_getInstanceMethod(viewClass, @selector(becomeFirstResponder));
        if (m1) {
            orig_becomeFirstResponder = (void *)method_getImplementation(m1);
            method_setImplementation(m1, (IMP)new_becomeFirstResponder);
        }
        
        Class windowClass = [UIWindow class];
        Method m2 = class_getInstanceMethod(windowClass, @selector(sendEvent:));
        if (m2) {
            orig_windowSendEvent = (void *)method_getImplementation(m2);
            method_setImplementation(m2, (IMP)new_windowSendEvent);
        }
        
        Class vcClass = [UIViewController class];
        Method m3 = class_getInstanceMethod(vcClass, @selector(viewWillDisappear:));
        if (m3) {
            orig_viewWillDisappear = (void *)method_getImplementation(m3);
            method_setImplementation(m3, (IMP)new_viewWillDisappear);
        }
        
        // 【已修复编译错误】移除了多余的赋值符号
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        
        [center addObserver:fixer selector:@selector(keyboardWillShowOrHide) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:fixer selector:@selector(keyboardWillShowOrHide) name:UIKeyboardDidHideNotification object:nil];
        
        [center addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
    });
}

- (void)onLockOrBackground {
    gWGEAppIsLockedState = YES;
    gWGEAppTransitionActive = YES;
    gWGEIsAppLockScreenShowing = YES;
}

- (void)onUnlockOrActive {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gWGEAppTransitionActive = NO;
        gWGEAppIsLockedState = NO;
        WGERunFullCleanup(); 
    });
}

- (void)keyboardWillShowOrHide {
    if (!gWGEIsAppLockScreenShowing) {
        WGERunFullCleanup();
    }
}

- (void)onAppUnlockSuccess {
    gWGEIsAppLockScreenShowing = NO;
    
    // 强制让当前整个App所有输入框不论在哪，立刻吐出焦点，确保解锁页面的 textField 在被销毁前，先安全地退弹键盘
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    
    // 紧接着配合超高频、长时间跨度的立体式消杀，彻底粉碎转场动画期间由于图层残留导致的各种恶心阴影
    WGERunFullCleanup();
    
    for (int i = 1; i <= 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WGERunFullCleanup();
        });
    }
}

@end
