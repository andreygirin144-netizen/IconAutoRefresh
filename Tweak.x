#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBHIconModel : NSObject
- (SBIcon *)expectedIconForDisplayIdentifier:(NSString *)bundleID;
- (BOOL)isIconVisible:(id)icon;
@end

@interface SBHIconManager : NSObject
- (SBHIconModel *)iconModel;
- (void)reloadIcons;
- (void)addNewIconToFirstAvailablePage:(id)icon animate:(BOOL)animate;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
- (void)addNewIconToFirstAvailablePage:(id)icon animate:(BOOL)animate;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
@end

@interface LSApplicationProxy : NSObject
- (NSString *)bundleIdentifier;
- (BOOL)isInstalled;
@end

static void PerformIconRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SBIconController *controller = [NSClassFromString(@"SBIconController") sharedInstance];
        if (!controller) return;

        SBHIconManager *iconManager = nil;
        if ([controller respondsToSelector:@selector(iconManager)]) {
            iconManager = [controller iconManager];
        }

        SBHIconModel *model = nil;
        if (iconManager && [iconManager respondsToSelector:@selector(iconModel)]) {
            model = [iconManager iconModel];
        }

        LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
        if (!model || !workspace) return;

        NSArray *allApps = [workspace allApplications];

        for (LSApplicationProxy *appProxy in allApps) {
            if (![appProxy respondsToSelector:@selector(bundleIdentifier)]) continue;
            
            NSString *bundleID = [appProxy bundleIdentifier];
            if (!bundleID) continue;

            SBIcon *icon = nil;
            if ([model respondsToSelector:@selector(expectedIconForDisplayIdentifier:)]) {
                icon = [model expectedIconForDisplayIdentifier:bundleID];
            }

            if (!icon) continue;

            BOOL isVisible = NO;
            if ([model respondsToSelector:@selector(isIconVisible:)]) {
                isVisible = [model isIconVisible:icon];
            }

            if (!isVisible) {
                if ([controller respondsToSelector:@selector(addNewIconToFirstAvailablePage:animate:)]) {
                    [controller addNewIconToFirstAvailablePage:icon animate:NO];
                } else if (iconManager && [iconManager respondsToSelector:@selector(addNewIconToFirstAvailablePage:animate:)]) {
                    [iconManager addNewIconToFirstAvailablePage:icon animate:NO];
                }
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
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
