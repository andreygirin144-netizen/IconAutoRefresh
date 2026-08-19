#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#pragma mark - Logging

static NSString *const kIARLogPath =
    @"/var/mobile/IconAutoRefresh.log";

static dispatch_source_t gTimer = nil;
static NSMutableSet<NSString *> *gKnownBundleIDs = nil;

static void IARLog(NSString *format, ...) {

    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format
                               arguments:args];

    va_end(args);

    NSLog(@"[IconAutoRefresh] %@", message);

    NSString *line =
        [NSString stringWithFormat:@"[%@] %@\n",
                                   [NSDate date],
                                   message];

    NSFileManager *fm =
        [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:kIARLogPath]) {
        [fm createFileAtPath:kIARLogPath
                    contents:nil
                  attributes:nil];
    }

    NSFileHandle *handle =
        [NSFileHandle fileHandleForWritingAtPath:kIARLogPath];

    if (handle) {
        [handle seekToEndOfFile];

        [handle writeData:
            [line dataUsingEncoding:NSUTF8StringEncoding]];

        [handle closeFile];
    }
}

#pragma mark - LaunchServices

static NSArray *IARGetInstalledApplications(void) {

    IARLog(@"IARGetInstalledApplications()");

    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {
        IARLog(@"ERROR: LSApplicationWorkspace not found");
        return nil;
    }

    SEL defaultWorkspace =
        NSSelectorFromString(@"defaultWorkspace");

    if (![workspaceClass respondsToSelector:defaultWorkspace]) {
        IARLog(@"ERROR: defaultWorkspace unavailable");
        return nil;
    }

    id workspace =
        ((id (*)(id, SEL))objc_msgSend)
        (workspaceClass, defaultWorkspace);

    if (!workspace) {
        IARLog(@"ERROR: defaultWorkspace returned nil");
        return nil;
    }

    SEL allInstalled =
        NSSelectorFromString(@"allInstalledApplications");

    if (![workspace respondsToSelector:allInstalled]) {
        IARLog(@"ERROR: allInstalledApplications unavailable");
        return nil;
    }

    NSArray *apps =
        ((id (*)(id, SEL))objc_msgSend)
        (workspace, allInstalled);

    if (!apps) {
        IARLog(@"ERROR: allInstalledApplications returned nil");
        return nil;
    }

    IARLog(@"LaunchServices returned %lu applications",
           (unsigned long)apps.count);

    return apps;
}

static NSString *IARGetBundleID(id application) {

    if (!application)
        return nil;

    SEL selector =
        NSSelectorFromString(@"bundleIdentifier");

    if ([application respondsToSelector:selector]) {

        return ((id (*)(id, SEL))objc_msgSend)
            (application, selector);
    }

    selector =
        NSSelectorFromString(@"applicationIdentifier");

    if ([application respondsToSelector:selector]) {

        return ((id (*)(id, SEL))objc_msgSend)
            (application, selector);
    }

    return nil;
}

static NSSet<NSString *> *IARGetBundleIDs(void) {

    NSArray *applications =
        IARGetInstalledApplications();

    if (!applications)
        return nil;

    NSMutableSet *result =
        [NSMutableSet set];

    for (id application in applications) {

        NSString *bundleID =
            IARGetBundleID(application);

        if (bundleID.length > 0) {
            [result addObject:bundleID];
        }
    }

    return result;
}

#pragma mark - SpringBoard Icon Model

static void IARDebugIconModel(NSString *bundleID) {

    if (![NSThread isMainThread]) {

        dispatch_async(dispatch_get_main_queue(), ^{
            IARDebugIconModel(bundleID);
        });

        return;
    }

    IARLog(@"================================");
    IARLog(@"BEGIN ICON DEBUG");
    IARLog(@"Bundle ID: %@", bundleID);

    /*
     * SBIconController
     */

    Class controllerClass =
        NSClassFromString(@"SBIconController");

    if (!controllerClass) {
        IARLog(@"ERROR: SBIconController not found");
        return;
    }

    IARLog(@"SBIconController class found");

    SEL sharedInstance =
        NSSelectorFromString(@"sharedInstance");

    if (![controllerClass respondsToSelector:sharedInstance]) {
        IARLog(@"ERROR: sharedInstance unavailable");
        return;
    }

    id controller =
        ((id (*)(id, SEL))objc_msgSend)
        (controllerClass, sharedInstance);

    if (!controller) {
        IARLog(@"ERROR: SBIconController sharedInstance = nil");
        return;
    }

    IARLog(@"SBIconController = %@", controller);

    /*
     * SBHIconManager
     */

    SEL iconManagerSelector =
        NSSelectorFromString(@"iconManager");

    if (![controller respondsToSelector:iconManagerSelector]) {
        IARLog(@"ERROR: iconManager selector unavailable");
        return;
    }

    id iconManager =
        ((id (*)(id, SEL))objc_msgSend)
        (controller, iconManagerSelector);

    if (!iconManager) {
        IARLog(@"ERROR: iconManager = nil");
        return;
    }

    IARLog(@"SBHIconManager = %@", iconManager);

    /*
     * SBHIconModel
     */

    SEL iconModelSelector =
        NSSelectorFromString(@"iconModel");

    if (![iconManager respondsToSelector:iconModelSelector]) {
        IARLog(@"ERROR: iconModel selector unavailable");
        return;
    }

    id iconModel =
        ((id (*)(id, SEL))objc_msgSend)
        (iconManager, iconModelSelector);

    if (!iconModel) {
        IARLog(@"ERROR: iconModel = nil");
        return;
    }

    IARLog(@"SBHIconModel = %@", iconModel);

    /*
     * Root folder
     */

    SEL rootFolderSelector =
        NSSelectorFromString(@"rootFolder");

    id rootFolder = nil;

    if ([iconManager respondsToSelector:rootFolderSelector]) {

        rootFolder =
            ((id (*)(id, SEL))objc_msgSend)
            (iconManager, rootFolderSelector);
    }

    if (!rootFolder) {
        IARLog(@"WARNING: rootFolder = nil");
    } else {
        IARLog(@"SBRootFolder = %@", rootFolder);
    }

    /*
     * Get icon using expectedIconForDisplayIdentifier:
     */

    id icon = nil;

    SEL expectedSelector =
        NSSelectorFromString(
            @"expectedIconForDisplayIdentifier:"
        );

    if ([iconModel respondsToSelector:expectedSelector]) {

        IARLog(
            @"Trying expectedIconForDisplayIdentifier:"
        );

        icon =
            ((id (*)(id, SEL, id))objc_msgSend)
            (iconModel,
             expectedSelector,
             bundleID);

        IARLog(
            @"expectedIcon result = %@",
            icon
        );

    } else {

        IARLog(
            @"expectedIconForDisplayIdentifier: unavailable"
        );
    }

    /*
     * Get icon using applicationIconForBundleIdentifier:
     */

    if (!icon) {

        SEL applicationIconSelector =
            NSSelectorFromString(
                @"applicationIconForBundleIdentifier:"
            );

        if ([iconModel respondsToSelector:
                              applicationIconSelector]) {

            IARLog(
                @"Trying applicationIconForBundleIdentifier:"
            );

            icon =
                ((id (*)(id, SEL, id))objc_msgSend)
                (iconModel,
                 applicationIconSelector,
                 bundleID);

            IARLog(
                @"applicationIcon result = %@",
                icon
            );

        } else {

            IARLog(
                @"applicationIconForBundleIdentifier: unavailable"
            );
        }
    }

    /*
     * If there is no icon, test addApplicationIcon...
     */

    if (!icon) {

        SEL addApplicationSelector =
            NSSelectorFromString(
                @"addApplicationIconForBundleIdentifier:"
            );

        if ([iconModel respondsToSelector:
                              addApplicationSelector]) {

            IARLog(
                @"Trying addApplicationIconForBundleIdentifier:"
            );

            icon =
                ((id (*)(id, SEL, id))objc_msgSend)
                (iconModel,
                 addApplicationSelector,
                 bundleID);

            IARLog(
                @"addApplicationIcon result = %@",
                icon
            );

        } else {

            IARLog(
                @"addApplicationIconForBundleIdentifier: unavailable"
            );
        }
    }

    if (!icon) {

        IARLog(
            @"FATAL: no SBIcon could be obtained"
        );

        IARLog(@"END ICON DEBUG");

        return;
    }

    IARLog(
        @"SUCCESS: SBIcon obtained: %@",
        icon
    );

    /*
     * Get bundle ID back from SBIcon.
     */

    SEL iconBundleSelector =
        NSSelectorFromString(
            @"applicationBundleID"
        );

    if ([icon respondsToSelector:iconBundleSelector]) {

        NSString *iconBundleID =
            ((id (*)(id, SEL))objc_msgSend)
            (icon, iconBundleSelector);

        IARLog(
            @"SBIcon applicationBundleID = %@",
            iconBundleID
        );
    } else {

        IARLog(
            @"SBIcon has no applicationBundleID selector"
        );
    }

    /*
     * Check rootFolder containsIcon:
     */

    BOOL containsIcon = NO;

    if (rootFolder) {

        SEL containsSelector =
            NSSelectorFromString(
                @"containsIcon:"
            );

        if ([rootFolder respondsToSelector:
                             containsSelector]) {

            containsIcon =
                ((BOOL (*)(id, SEL, id))objc_msgSend)
                (rootFolder,
                 containsSelector,
                 icon);

            IARLog(
                @"rootFolder containsIcon = %d",
                containsIcon
            );

        } else {

            IARLog(
                @"rootFolder containsIcon: unavailable"
            );
        }
    }

    if (containsIcon) {

        IARLog(
            @"RESULT: icon is ALREADY on Home Screen"
        );

        if ([iconModel respondsToSelector:
                         @selector(saveIconState)]) {

            IARLog(
                @"Calling saveIconState"
            );

            ((void (*)(id, SEL))objc_msgSend)
                (iconModel,
                 @selector(saveIconState));
        }

        IARLog(@"END ICON DEBUG");

        return;
    }

    /*
     * Icon is not currently in root folder.
     */

    IARLog(
        @"RESULT: icon is NOT on Home Screen"
    );

    /*
     * Check controller add method.
     */

    SEL addSelector =
        NSSelectorFromString(
            @"addNewIconToFirstAvailablePage:animate:"
        );

    BOOL controllerCanAdd =
        [controller respondsToSelector:addSelector];

    BOOL managerCanAdd =
        [iconManager respondsToSelector:addSelector];

    IARLog(
        @"SBIconController add method available = %d",
        controllerCanAdd
    );

    IARLog(
        @"SBHIconManager add method available = %d",
        managerCanAdd
    );

    /*
     * DO NOT modify anything yet.
     *
     * This first diagnostic build only reports
     * whether the required method exists.
     */

    IARLog(
        @"Diagnostic mode: NOT adding icon yet"
    );

    /*
     * Save state selector availability.
     */

    BOOL canSave =
        [iconModel respondsToSelector:
                     @selector(saveIconState)];

    IARLog(
        @"saveIconState available = %d",
        canSave
    );

    IARLog(@"END ICON DEBUG");
}

#pragma mark - Poll

static void IARPoll(void) {

    IARLog(@"========== POLL ==========");

    NSSet<NSString *> *current =
        IARGetBundleIDs();

    if (!current) {

        IARLog(
            @"POLL FAILED"
        );

        return;
    }

    if (!gKnownBundleIDs) {

        gKnownBundleIDs =
            [current mutableCopy];

        IARLog(
            @"BASELINE: %lu applications",
            (unsigned long)current.count
        );

        return;
    }

    NSMutableSet *newApps =
        [current mutableCopy];

    [newApps minusSet:gKnownBundleIDs];

    gKnownBundleIDs =
        [current mutableCopy];

    if (newApps.count == 0) {

        IARLog(
            @"No new applications"
        );

        return;
    }

    IARLog(
        @"NEW APPLICATIONS: %lu",
        (unsigned long)newApps.count
    );

    for (NSString *bundleID in newApps) {

        IARLog(
            @"NEW BUNDLE ID: %@",
            bundleID
        );

        /*
         * Give LaunchServices/SpringBoard time
         * to finish registration.
         */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{

                IARDebugIconModel(bundleID);

            }
        );
    }
}

#pragma mark - Timer

static void IARStartTimer(void) {

    if (gTimer) {

        IARLog(
            @"Timer already exists"
        );

        return;
    }

    IARLog(
        @"Creating polling timer"
    );

    gTimer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_main_queue()
        );

    if (!gTimer) {

        IARLog(
            @"ERROR: timer creation failed"
        );

        return;
    }

    dispatch_source_set_timer(
        gTimer,
        dispatch_time(
            DISPATCH_TIME_NOW,
            1 * NSEC_PER_SEC
        ),
        3 * NSEC_PER_SEC,
        500 * NSEC_PER_MSEC
    );

    dispatch_source_set_event_handler(
        gTimer,
        ^{

            IARLog(
                @"Timer fired"
            );

            IARPoll();

        }
    );

    dispatch_resume(gTimer);

    IARLog(
        @"Polling timer started successfully"
    );
}

#pragma mark - Constructor

%ctor {

    @autoreleasepool {

        IARLog(
            @"================================"
        );

        IARLog(
            @"IconAutoRefresh loaded"
        );

        IARLog(
            @"Starting application monitor"
        );

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                IARStartTimer();

            }
        );

        IARLog(
            @"Initialization complete"
        );
    }
}
