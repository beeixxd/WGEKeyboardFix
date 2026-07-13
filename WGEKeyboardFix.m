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
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center addObserver:fixer selector:@selector(onAppUnlockSuccess) name:@"WGEAppUnlockScreenDidDismissNotification" object:nil];
        });
    });
}

- (void)onAppUnlockSuccess {
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
    
    UIWindow *targetLockWindow = nil;
    for (UIWindow *w in allWindows) {
        NSString *className = NSStringFromClass([w class]);
        if ([className rangeOfString:@"Passcode"].location != NSNotFound ||
            [className rangeOfString:@"Secure"].location != NSNotFound ||
            [className rangeOfString:@"Lock"].location != NSNotFound) {
            targetLockWindow = w;
            break;
        }
    }
    
    if (!targetLockWindow && allWindows.count > 1) {
        targetLockWindow = [UIApplication sharedApplication].keyWindow;
    }
    
    if (targetLockWindow) {
        targetLockWindow.alpha = 0.0;
        [targetLockWindow endEditing:YES];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            targetLockWindow.hidden = YES;
        });
    } else {
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
        for (UIWindow *w in allWindows) {
            [w endEditing:YES];
        }
    }
}

@end
