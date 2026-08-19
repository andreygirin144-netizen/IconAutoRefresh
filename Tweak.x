#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

@interface SBHIconManager : NSObject
- (id)iconModel;
- (void)reloadIcons;
@end

@interface SBHIconModel : NSObject
- (void)layout;
- (void)reload;
@end

@interface SBIconModel : NSObject
- (void)layout;
- (void)reload;
- (void)reloadIconState;
- (void)applicationIconAdded:(id)arg1;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
- (SBIconModel *)model;
- (void)refreshIconState;
@end

static void PerformIconRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SBIconController *controller = [NSClassFromString(@"SBIconController") sharedInstance];
        if (!controller) return;

        if ([controller respondsToSelector:@selector(iconManager)]) {
            SBHIconManager *iconManager = [controller iconManager];
            
            if ([iconManager respondsToSelector:@selector(reloadIcons)]) {
                [iconManager reloadIcons];
            }
            
            SBHIconModel *model = [iconManager iconModel];
            if ([model respondsToSelector:@selector(layout)]) {
                [model layout];
            } else if ([model respondsToSelector:@selector(reload)]) {
                [model reload];
            }
        } else if ([controller respondsToSelector:@selector(model)]) {
            SBIconModel *model = [controller model];
            if (model) {
                if ([model respondsToSelector:@selector(reloadIconState)]) {
                    [model reloadIconState];
                } else if ([model respondsToSelector:@selector(reload)]) {
                    [model reload];
                } else if ([model respondsToSelector:@selector(applicationIconAdded:)]) {
                    [model applicationIconAdded:nil];
                } else if ([model respondsToSelector:@selector(layout)]) {
                    [model layout];
                }
            }
        }
        
        if ([controller respondsToSelector:@selector(refreshIconState)]) {
            [controller refreshIconState];
        }
    });
}

static void DarwinNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    PerformIconRefresh();
}

%hook LSApplicationWorkspace

- (BOOL)registerApplication:(id)arg1 {
    BOOL result = %orig(arg1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.custom.iconrefresh.trigger"),
            NULL, NULL, YES
        );
    });
    return result;
}

- (BOOL)registerPlugin:(id)arg1 {
    BOOL result = %orig(arg1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.custom.iconrefresh.trigger"),
            NULL, NULL, YES
        );
    });
    return result;
}

%end

%group MobileInstallerHooks

%hook MobileInstaller

- (void)installApplication:(id)arg1 withOptions:(id)arg2 completion:(id)arg3 {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.custom.iconrefresh.trigger"),
            NULL, NULL, YES
        );
    });
}

- (void)installApplication:(id)arg1 withCompletion:(id)arg2 {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.custom.iconrefresh.trigger"),
            NULL, NULL, YES
        );
    });
}

%end

%end

%ctor {
    %init(_ungrouped);
    
    if (%c(MobileInstaller)) {
        %init(MobileInstallerHooks);
    }
    
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)DarwinNotificationCallback,
            CFSTR("com.custom.iconrefresh.trigger"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
