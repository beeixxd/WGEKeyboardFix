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
    // 如果处于系统锁屏状态，绝对不要乱动，让系统原生的锁屏自己处理
    if (gWGEAppIsLockedState) {
        return;
    }
    
    // 如果应用自己的解锁界面还在，我们只清理残留的僵尸阴影，不盲目调用 resignFirstResponder 撤销光标
    if (!gWGEIsAppLockScreenShowing) {
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    }

    for (UIWindow *w in WGEAllWindows()) {
        NSString *windowClassName = NSStringFromClass([w class]);
        
        // 绝对放行系统敏感密码窗口
        if ([windowClassName rangeOfString:@"Passcode"].location != NSNotFound ||
            [windowClassName rangeOfString:@"Secure"].location != NSNotFound) {
            continue;
        }

        // 【重磅修复】如果是在展示应用解锁页，只清理可能卡死的“键盘阴影窗口”，绝不隐藏正在尝试弹起的正常文本窗口
        if ([windowClassName containsString:@"TextEffects"] || [windowClassName containsString:@"Keyboard"]) {
            if (!gWGEIsAppLockScreenShowing) {
                // 进入首页了，全盘抹杀
                w.hidden = YES;
                w.alpha = 0.0;
                CGRect frame = w.frame;
                frame.size.height = 0;
                w.frame = frame;
            } else {
                // 如果在解锁页，且当前并没有真正弹起键盘（高度很小或为0），说明这是卡死的残影窗口，将其隐形
                if (w.frame.size.height < 100) {
                    w.alpha = 0.0;
                }
            }
        }

        // 针对图层级别的特殊清理
        for (UIView *subview in [w subviews]) {
            NSString *subName = NSStringFromClass([subview class]);
            if ([subName containsString:@"Dimming"] || 
                [subName containsString:@"Shadow"] || 
                [subName containsString:@"Corner"]) {
                
                // 如果已经解锁进入首页，或者这个阴影孤零零存在（没有键盘实体），直接拔除
                if (!gWGEIsAppLockScreenShowing || !w.keyWindow) {
                    subview.hidden = YES;
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
        // 【核心修复】应用解锁页展示期间，只要控件请求拉起键盘，我们100%放行，不附加任何额外清理，确保不卡死
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
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        
        // 核心：监听系统键盘本身的生命周期，用来抓取并消灭那些有阴影无实体的“僵尸键盘图层”
        [center addObserver:fixer selector:@selector(keyboardWillShowOrHide) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:fixer selector:@selector(keyboardWillShowOrHide) name:UIKeyboardDidHideNotification object:nil];
        
        // 监听应用自身解锁成功/收起的通知
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
    // 键盘状态有变动时，顺手检查并干掉脱离控件控制的孤立阴影图层
    if (!gWGEIsAppLockScreenShowing) {
        WGERunFullCleanup();
    }
}

- (void)onAppUnlockSuccess {
    gWGEIsAppLockScreenShowing = NO;
    
    // 【终极重写】解锁成功去首页时，由于视图层级正在大规模切换，单次清理可能无效。
    // 我们在这里采用一个分时梯度清理，连续在0秒、0.1秒、0.3秒进行全方位地毯式消杀，确保阴影死透。
    WGERunFullCleanup();
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WGERunFullCleanup();
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WGERunFullCleanup();
    });
}

@end
