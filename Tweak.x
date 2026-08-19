#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Private interfaces (best-effort, may not exist on all versions)

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBFolder : NSObject
- (BOOL)containsIcon:(id)icon;
@end

@interface SBRootFolder : SBFolder
@end

@interface SBHIconModel : NSObject
- (SBIcon *)expectedIconForDisplayIdentifier:(NSString *)bundleID;
- (SBIcon *)applicationIconForBundleIdentifier:(NSString *)bundleID;
- (SBIcon *)addApplicationIconForBundleIdentifier:(NSString *)bundleID;
- (void)saveIconState;
@end

@interface SBHIconManager : NSObject
- (SBHIconModel *)iconModel;
- (SBRootFolder *)rootFolder;
- (void)addNewIconToFirstAvailablePage:(id)icon animate:(BOOL)animate;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
- (void)addNewIconToFirstAvailablePage:(id)icon animate:(BOOL)animate;
@end

#pragma mark - Core logic

static void ProcessBundleID(NSString *bundleID) {
    NSLog(@"[IconAutoRefresh] ProcessBundleID: %@", bundleID);

    Class controllerClass = NSClassFromString(@"SBIconController");
    if (!controllerClass) {
        NSLog(@"[IconAutoRefresh] SBIconController class not found");
        return;
    }

    SBIconController *controller = [controllerClass sharedInstance];
    if (!controller) {
        NSLog(@"[IconAutoRefresh] sharedInstance is nil");
        return;
    }

    SBHIconManager *iconManager = nil;
    if ([controller respondsToSelector:@selector(iconManager)]) {
        iconManager = [controller iconManager];
    }
    if (!iconManager) {
        NSLog(@"[IconAutoRefresh] iconManager is nil / not available");
        return;
    }

    SBHIconModel *model = nil;
    if ([iconManager respondsToSelector:@selector(iconModel)]) {
        model = [iconManager iconModel];
    }

    SBRootFolder *rootFolder = nil;
    if ([iconManager respondsToSelector:@selector(rootFolder)]) {
        rootFolder = [iconManager rootFolder];
    }

    if (!model || !rootFolder) {
        NSLog(@"[IconAutoRefresh] model=%@ rootFolder=%@", model, rootFolder);
        return;
    }

    SBIcon *icon = nil;
    if ([model respondsToSelector:@selector(expectedIconForDisplayIdentifier:)]) {
        icon = [model expectedIconForDisplayIdentifier:bundleID];
    }
    if (!icon && [model respondsToSelector:@selector(applicationIconForBundleIdentifier:)]) {
        icon = [model applicationIconForBundleIdentifier:bundleID];
    }
    if (!icon && [model respondsToSelector:@selector(addApplicationIconForBundleIdentifier:)]) {
        icon = [model addApplicationIconForBundleIdentifier:bundleID];
    }

    if (!icon) {
        NSLog(@"[IconAutoRefresh] Could not resolve icon for %@", bundleID);
        return;
    }

    BOOL isOnHomeScreen = NO;
    if ([rootFolder respondsToSelector:@selector(containsIcon:)]) {
        isOnHomeScreen = [rootFolder containsIcon:icon];
    }

    NSLog(@"[IconAutoRefresh] icon=%@ isOnHomeScreen=%d", icon, isOnHomeScreen);

    if (!isOnHomeScreen) {
        if ([controller respondsToSelector:@selector(addNewIconToFirstAvailablePage:animate:)]) {
            [controller addNewIconToFirstAvailablePage:icon animate:NO];
            NSLog(@"[IconAutoRefresh] Added icon via SBIconController");
        } else if ([iconManager respondsToSelector:@selector(addNewIconToFirstAvailablePage:animate:)]) {
            [iconManager addNewIconToFirstAvailablePage:icon animate:NO];
            NSLog(@"[IconAutoRefresh] Added icon via SBHIconManager");
        } else {
            NSLog(@"[IconAutoRefresh] No method found to add icon to homescreen");
        }
    }

    if ([model respondsToSelector:@selector(saveIconState)]) {
        [model saveIconState];
    }
}

#pragma mark - Darwin notification driven refresh
// installd / lsd broadcast this notification whenever the installed-apps
// list changes (install, update, uninstall). This is far more reliable
// than guessing a private SpringBoard method name per iOS version.

static void HandleAppInstallNotification(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    NSString *notifName = (__bridge NSString *)name;
    NSLog(@"[IconAutoRefresh] Darwin notification received: %@", notifName);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // We don't get a bundle ID directly from this notification, so we
        // do a full pass: ask LSApplicationWorkspace for all installed apps
        // and re-check which ones are missing from the home screen.
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)]
                        ? [workspaceClass performSelector:@selector(defaultWorkspace)]
                        : nil;
        if (!workspace) {
            NSLog(@"[IconAutoRefresh] LSApplicationWorkspace unavailable");
            return;
        }

        NSArray *allApps = nil;
        if ([workspace respondsToSelector:@selector(allInstalledApplications)]) {
            allApps = [workspace performSelector:@selector(allInstalledApplications)];
        }

        if (!allApps) {
            NSLog(@"[IconAutoRefresh] Could not enumerate installed applications");
            return;
        }

        for (id proxy in allApps) {
            NSString *bundleID = nil;
            if ([proxy respondsToSelector:@selector(bundleIdentifier)]) {
                bundleID = [proxy performSelector:@selector(bundleIdentifier)];
            } else if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
                bundleID = [proxy performSelector:@selector(applicationIdentifier)];
            }
            if (bundleID) {
                ProcessBundleID(bundleID);
            }
        }
    });
}

%ctor {
    NSLog(@"[IconAutoRefresh] Tweak loaded, registering Darwin notifications");

    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();

    // Cover the common notification names seen across iOS versions/tools
    // (LaunchServices / installd / TrollStore-style installs).
    const char *notifNames[] = {
        "com.apple.mobile.installation.installed",
        "com.apple.LaunchServices.applicationRegistered",
        "com.apple.mobile.application_installed"
    };

    for (int i = 0; i < 3; i++) {
        CFNotificationCenterAddObserver(
            darwinCenter,
            NULL,
            HandleAppInstallNotification,
            (__bridge CFStringRef)[NSString stringWithUTF8String:notifNames[i]],
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }

    %init;
}
