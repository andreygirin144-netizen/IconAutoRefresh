#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)bundleID;
- (NSString *)bundleIdentifier;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
- (NSArray *)observers;
@end

@interface SBHIconManager : NSObject
- (id)iconModel;
- (void)reloadIcons;
@end

@interface SBHIconModel : NSObject
- (void)layout;
- (void)reload;
- (id)expectedIconForDisplayIdentifier:(NSString *)arg1;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
@end

static void PerformIconRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
        
        if (workspace && [workspace respondsToSelector:@selector(observers)]) {
            NSArray *allApps = [workspace allApplications];
            
            for (id observer in [workspace observers]) {
                if ([observer respondsToSelector:@selector(applicationsDidInstall:)]) {
                    [observer applicationsDidInstall:allApps];
                }
            }
        }

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
        }
    });
}

static void DarwinNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    PerformIconRefresh();
}

%hook LSApplicationWorkspace

- (BOOL)registerApplication:(id)arg1 {
    BOOL result = %orig(arg1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.custom.iconrefresh.trigger"),
            NULL, NULL, YES
        );
    });
    return result;
}

%end

%ctor {
    %init(_ungrouped);
    
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
