#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - File-based logging
// Writing to a plain text file sidesteps having to fight with `log stream`
// quoting in a terminal app. The file can be opened with any file manager
// (Files app, Filza, iFile, or `cat` in NewTerm with no special characters).

static NSString *const kIARLogPath = @"/var/mobile/IconAutoRefresh.log";

static void IARLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // Still emit to the normal system log too, in case someone is streaming it.
    NSLog(@"%@", message);

    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                           dateStyle:NSDateFormatterShortStyle
                                                           timeStyle:NSDateFormatterMediumStyle];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kIARLogPath]) {
        [fm createFileAtPath:kIARLogPath contents:nil attributes:nil];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kIARLogPath];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

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
    IARLog(@"ProcessBundleID: %@", bundleID);

    Class controllerClass = NSClassFromString(@"SBIconController");
    if (!controllerClass) {
        IARLog(@"SBIconController class not found");
        return;
    }

    SBIconController *controller = [controllerClass sharedInstance];
    if (!controller) {
        IARLog(@"sharedInstance is nil");
        return;
    }

    SBHIconManager *iconManager = nil;
    if ([controller respondsToSelector:@selector(iconManager)]) {
        iconManager = [controller iconManager];
    }
    if (!iconManager) {
        IARLog(@"iconManager is nil / not available");
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
        IARLog(@"model=%@ rootFolder=%@", model, rootFolder);
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
        IARLog(@"Could not resolve icon for %@", bundleID);
        return;
    }

    BOOL isOnHomeScreen = NO;
    if ([rootFolder respondsToSelector:@selector(containsIcon:)]) {
        isOnHomeScreen = [rootFolder containsIcon:icon];
    }

    IARLog(@"icon=%@ isOnHomeScreen=%d", icon, isOnHomeScreen);

    if (!isOnHomeScreen) {
        if ([controller respondsToSelector:@selector(addNewIconToFirstAvailablePage:animate:)]) {
            [controller addNewIconToFirstAvailablePage:icon animate:NO];
            IARLog(@"Added icon via SBIconController");
        } else if ([iconManager respondsToSelector:@selector(addNewIconToFirstAvailablePage:animate:)]) {
            [iconManager addNewIconToFirstAvailablePage:icon animate:NO];
            IARLog(@"Added icon via SBHIconManager");
        } else {
            IARLog(@"No method found to add icon to homescreen");
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
    IARLog(@"Darwin notification received: %@", notifName);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // We don't get a bundle ID directly from this notification, so we
        // do a full pass: ask LSApplicationWorkspace for all installed apps
        // and re-check which ones are missing from the home screen.
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)]
                        ? [workspaceClass performSelector:@selector(defaultWorkspace)]
                        : nil;
        if (!workspace) {
            IARLog(@"LSApplicationWorkspace unavailable");
            return;
        }

        NSArray *allApps = nil;
        if ([workspace respondsToSelector:@selector(allInstalledApplications)]) {
            allApps = [workspace performSelector:@selector(allInstalledApplications)];
        }

        if (!allApps) {
            IARLog(@"Could not enumerate installed applications");
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

#pragma mark - Polling fallback
// None of the Darwin notifications fired for a TrollStore Lite install in
// testing, so we fall back to a simple, guaranteed-to-work approach:
// periodically snapshot the installed bundle IDs and diff against the
// previous snapshot. When a new bundle ID shows up, process it. This does
// not depend on any private notification name being correct.

static NSMutableSet<NSString *> *gKnownBundleIDs = nil;

static NSArray *IARFetchAllBundleIDs(void) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)]
                    ? [workspaceClass performSelector:@selector(defaultWorkspace)]
                    : nil;
    if (!workspace) {
        return nil;
    }

    NSArray *allApps = nil;
    if ([workspace respondsToSelector:@selector(allInstalledApplications)]) {
        allApps = [workspace performSelector:@selector(allInstalledApplications)];
    }
    if (!allApps) {
        return nil;
    }

    NSMutableArray *bundleIDs = [NSMutableArray array];
    for (id proxy in allApps) {
        NSString *bundleID = nil;
        if ([proxy respondsToSelector:@selector(bundleIdentifier)]) {
            bundleID = [proxy performSelector:@selector(bundleIdentifier)];
        } else if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
            bundleID = [proxy performSelector:@selector(applicationIdentifier)];
        }
        if (bundleID) {
            [bundleIDs addObject:bundleID];
        }
    }
    return bundleIDs;
}

static void IARPollForNewApps(void) {
    NSArray *current = IARFetchAllBundleIDs();
    if (!current) {
        IARLog(@"Poll: could not fetch installed applications");
        return;
    }

    if (!gKnownBundleIDs) {
        // First run: just record the baseline, do not treat everything
        // that's already installed as "new".
        gKnownBundleIDs = [NSMutableSet setWithArray:current];
        IARLog(@"Poll: baseline captured, %lu apps", (unsigned long)gKnownBundleIDs.count);
        return;
    }

    NSMutableSet *currentSet = [NSMutableSet setWithArray:current];
    NSMutableSet *newOnes = [currentSet mutableCopy];
    [newOnes minusSet:gKnownBundleIDs];

    if (newOnes.count > 0) {
        IARLog(@"Poll: detected %lu new app(s)", (unsigned long)newOnes.count);
        for (NSString *bundleID in newOnes) {
            ProcessBundleID(bundleID);
        }
    }

    gKnownBundleIDs = currentSet;
}

%ctor {
    IARLog(@"Tweak loaded, registering Darwin notifications + polling fallback");

    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();

    // Keep the notification path too, in case it fires for other install
    // methods (Sileo/dpkg) even though it didn't for TrollStore Lite.
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

    // Poll every 3 seconds. Cheap: just an array diff, runs on a background
    // queue so it never blocks SpringBoard's main thread.
    dispatch_queue_t pollQueue = dispatch_queue_create("com.custom.iconautorefresh.poll", DISPATCH_QUEUE_SERIAL);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, pollQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 3 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            IARPollForNewApps();
        });
    });
    dispatch_resume(timer);

    %init;
}
