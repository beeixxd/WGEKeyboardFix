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
    
    // 如果已经解锁进入首页，全局无条件强制撤销所有光标响应
    if (!gWGEIsAppLockScreenShowing) {
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    }

    for (UIWindow *w in WGEAllWindows()) {
        NSString *windowClassName = NSStringFromClass([w class]);
        
        if ([windowClassName rangeOfString:@"Passcode"].location != NSNotFound ||
            [windowClassName rangeOfString:@"Secure"].location != NSNotFound) {
            continue;
        }

        BOOL isKeyboardWindow = [windowClassName containsString:@"TextEffects"] || [windowClassName containsString:@"Keyboard"];

        if (!gWGEIsAppLockScreenShowing) {
            // 【核心重置】如果已经在首页，针对键盘宿主窗口进行毁灭性拦截
            if (isKeyboardWindow) {
                w.hidden = YES;
                w.alpha = 0.0;
                CGRect frame = w.frame;
                frame.size.height = 0;
                w.frame = frame;
                // 强制让它的 rootViewController 放弃响应
                [w.rootViewController.view endEditing:YES];
            }
        } else {
            // 如果还在解锁页，但键盘窗口高度为0或极低，说明是卡死的假阴影窗口，将其隐形
            if (isKeyboardWindow && w.frame.size.height < 100) {
                w.alpha = 0.0;
            }
        }

        // 【最关键的深度消杀】遍历键盘窗口内部的所有子视图（阴影、遮罩、背景）
        // 系统之所以能显示阴影，是因为这些子视图还活着。我们直接把它们物理移除！
        for (UIView *subview in [w subviews]) {
            NSString *subName = NSStringFromClass([subview class]);
            if ([subName containsString:@"Dimming"] || 
                [subName containsString:@"Shadow"] || 
                [subName containsString:@"Corner"] ||
                [subName containsString:@"Keyboard"] ||
                [subName containsString:@"Background"]) { 
                
                if (!gWGEIsAppLockScreenShowing) {
                    subview.hidden = YES;
                    subview.alpha = 0.0;
                    CGRect frame = subview.frame;
                    frame.size.height = 0;
                    subview.frame = frame;
                    
                    // 彻底从图层树里拔掉，不给系统留任何做“渐隐动画”的物质基础
                    [subview removeFromSuperview];
                }
            }
        }
    }
}

static BOOL (*orig_becomeFirstResponder)(id, SEL);
static BOOL new_becomeFirstResponder(id self, SEL _cmd) {
    // 1. 如果解锁页正在显示，绿灯放行，保证能自动聚焦弹键盘
    if (gWGEIsAppLockScreenShowing) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    // 2. 锁屏或转场状态，直接放行系统
    if (gWGEAppIsLockedState || gWGEAppTransitionActive) {
        return orig_becomeFirstResponder(self, _cmd);
    }
    
    // 3. 已经在首页了，只要不是用户纯手动点击触发的，一律拦截并清理
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
    // 只要有页面消失，顺手清一下，查漏补缺
    if (!gWGEIsAppLockScreenShowing) {
        WGERunFullCleanup();
    }
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
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        
        [center addObserver:fixer selector:@selector(keyboardWillShowOrHide) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:fixer selector:@selector(keyboardWillShowOrHide) name:UIKeyboardDidHideNotification object:nil];
        
        // 核心：监听解锁成功的信号
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
    // 1. 瞬间关闭特权，转为首页最高防御防弹状态
    gWGEIsAppLockScreenShowing = NO;
    
    // 2. 立即斩断全App的光标第一响应者
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    
    // 3. 首次强力拔除阴影
    WGERunFullCleanup();
    
    // 4. 在接下来的 0.5 秒转场黄金期内，进行持续密集的五连环地毯式消杀（彻底粉碎任何系统延迟创建的渐变阴影图层）
    for (int i = 1; i <= 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WGERunFullCleanup();
        });
    }
}

@end
