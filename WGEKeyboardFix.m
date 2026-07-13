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
        NSString *className = NSStringFromClass([w class]);
        if ([className containsString:@"TextEffects"] || [className containsString:@"Keyboard"]) {
            [UIView animateWithDuration:0.25 animations:^{
                w.alpha = 0.0;
            } completion:^(BOOL finished) {
                w.hidden = YES;
                w.alpha = 1.0;
            }];
        }
    }
    
    for (int i = 1; i <= 4; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
                    if (w.hidden == NO && w.alpha > 0.0) {
                        [UIView animateWithDuration:0.15 animations:^{
                            w.alpha = 0.0;
                        } completion:^(BOOL finished) {
                            w.hidden = YES;
                            w.alpha = 1.0;
                        }];
                    }
                }
            }
        });
    }
}

@end
