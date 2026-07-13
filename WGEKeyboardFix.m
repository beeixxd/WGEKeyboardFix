#import <UIKit/UIKit.h>

static BOOL gWGEAppTransitionActive = NO;
static BOOL gWGEAppIsLockedState = NO;
static BOOL gWGEIsAppLockScreenShowing = YES;

@interface WGEKeyboardUltimatePerfectFixer : NSObject
@end

@implementation WGEKeyboardUltimatePerfectFixer

+ (void)load {
    static WGEKeyboardUltimatePerfectFixer *fixer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fixer = [[WGEKeyboardUltimatePerfectFixer alloc] init];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
            [center addObserver:fixer selector:@selector(onLockOrBackground) name:UIApplicationWillResignActiveNotification object:nil];
            [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationWillEnterForegroundNotification object:nil];
            [center addObserver:fixer selector:@selector(onUnlockOrActive) name:UIApplicationDidBecomeActiveNotification object:nil];
            [center addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
        });
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
    });
}

- (void)onAppUnlockSuccess {
    gWGEIsAppLockScreenShowing = NO;
    
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    
    NSMutableArray *allWindows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w) [allWindows addObject:w];
            }
        }
    }
    if (allWindows.count == 0) {
        NSArray *legacyWindows = [UIApplication sharedApplication].windows;
        if (legacyWindows) [allWindows addObjectsFromArray:legacyWindows];
    }
    
    for (UIWindow *w in allWindows) {
        [w endEditing:YES];
        NSString *className = NSStringFromClass([w class]);
        if ([className containsString:@"TextEffects"] || [className containsString:@"Keyboard"]) {
            w.hidden = YES;
            w.alpha = 0.0;
            CGRect frame = w.frame;
            frame.size.height = 0;
            w.frame = frame;
        }
    }
    
    for (int i = 1; i <= 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
            
            NSMutableArray *delayedWindows = [NSMutableArray array];
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) continue;
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                        if (w) [delayedWindows addObject:w];
                    }
                }
            }
            if (delayedWindows.count == 0) {
                NSArray *legacyWindows = [UIApplication sharedApplication].windows;
                if (legacyWindows) [delayedWindows addObjectsFromArray:legacyWindows];
            }
            
            for (UIWindow *w in delayedWindows) {
                NSString *className = NSStringFromClass([w class]);
                if ([className containsString:@"TextEffects"] || [className containsString:@"Keyboard"]) {
                    w.hidden = YES;
                    w.alpha = 0.0;
                    CGRect frame = w.frame;
                    frame.size.height = 0;
                    w.frame = frame;
                }
            }
        });
    }
}

@end
