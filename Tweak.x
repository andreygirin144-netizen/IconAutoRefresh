#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - Logging

static NSString *const kIARLogPath = @"/var/mobile/IconAutoRefresh.log";

static void IARLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSLog(@"[IconAutoRefresh] %@", message);

    NSString *line =
        [NSString stringWithFormat:@"[%@] %@\n",
         [NSDate date],
         message];

    NSFileManager *fm = [NSFileManager defaultManager];

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

#pragma mark - Private classes

@interface SBIcon : NSObject
@end

@interface SBApplicationIcon : SBIcon
@end

@interface SBIconModel : NSObject
@end

@interface SBHIconManager : NSObject
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
@end

#pragma mark - Runtime helpers

static id IARMsgSendID(id object, SEL selector) {
    if (!object || !selector)
        return nil;

    if (![object respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL IARMsgSendBool(id object, SEL selector) {
    if (!object || !selector)
        return NO;

    if (![object respondsToSelector:selector])
        return NO;

    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

static void IARMsgSendVoid(id object, SEL selector) {
    if (!object || !selector)
        return;

    if (![object respondsToSelector:selector])
        return;

    ((void (*)(id, SEL))objc_msgSend)(object, selector);
}

#pragma mark - LaunchServices

static NSArray *IARGetInstalledApplications(void) {

    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {
        IARLog(@"LSApplicationWorkspace not found");
        return nil;
    }

    SEL defaultWorkspaceSEL =
        NSSelectorFromString(@"defaultWorkspace");

    id workspace =
        IARMsgSendID(workspaceClass, defaultWorkspaceSEL);

    if (!workspace) {
        IARLog(@"defaultWorkspace unavailable");
        return nil;
    }

    SEL allAppsSEL =
        NSSelectorFromString(@"allInstalledApplications");

    NSArray *apps =
        IARMsgSendID(workspace, allAppsSEL);

    if (!apps) {
        IARLog(@"allInstalledApplications unavailable");
        return nil;
    }

    IARLog(@"LaunchServices returned %lu applications",
           (unsigned long)apps.count);

    return apps;
}

static NSArray *IARGetBundleIDs(void) {

    NSArray *apps = IARGetInstalledApplications();

    if (!apps)
        return nil;

    NSMutableArray *result =
        [NSMutableArray array];

    for (id app in apps) {

        NSString *bundleID = nil;

        SEL bundleIDSEL =
            NSSelectorFromString(@"bundleIdentifier");

        if ([app respondsToSelector:bundleIDSEL]) {
            bundleID =
                IARMsgSendID(app, bundleIDSEL);
        }

        if (!bundleID) {
            SEL applicationIdentifierSEL =
                NSSelectorFromString(@"applicationIdentifier");

            if ([app respondsToSelector:
                 applicationIdentifierSEL]) {

                bundleID =
                    IARMsgSendID(
                        app,
                        applicationIdentifierSEL
                    );
            }
        }

        if (bundleID.length > 0)
            [result addObject:bundleID];
    }

    return result;
}

#pragma mark - SpringBoard objects

static id IARGetIconController(void) {

    Class cls =
        NSClassFromString(@"SBIconController");

    if (!cls) {
        IARLog(@"SBIconController not found");
        return nil;
    }

    SEL sharedSEL =
        NSSelectorFromString(@"sharedInstance");

    id controller =
        IARMsgSendID(cls, sharedSEL);

    if (!controller)
        IARLog(@"SBIconController sharedInstance = nil");

    return controller;
}

static id IARGetIconManager(id controller) {

    SEL selector =
        NSSelectorFromString(@"iconManager");

    id manager =
        IARMsgSendID(controller, selector);

    if (!manager)
        IARLog(@"iconManager unavailable");

    return manager;
}

static id IARGetIconModel(id manager) {

    SEL selector =
        NSSelectorFromString(@"iconModel");

    id model =
        IARMsgSendID(manager, selector);

    if (!model)
        IARLog(@"iconModel unavailable");

    return model;
}

#pragma mark - Icon lookup

static id IARGetIconForBundleID(id model,
                                NSString *bundleID) {

    if (!model || !bundleID)
        return nil;

    SEL expectedSEL =
        NSSelectorFromString(
            @"expectedIconForDisplayIdentifier:"
        );

    if ([model respondsToSelector:expectedSEL]) {

        id icon =
            ((id (*)(id, SEL, id))objc_msgSend)(
                model,
                expectedSEL,
                bundleID
            );

        if (icon) {
            IARLog(@"expectedIconForDisplayIdentifier: %@",
                   icon);

            return icon;
        }
    }

    SEL applicationSEL =
        NSSelectorFromString(
            @"applicationIconForBundleIdentifier:"
        );

    if ([model respondsToSelector:applicationSEL]) {

        id icon =
            ((id (*)(id, SEL, id))objc_msgSend)(
                model,
                applicationSEL,
                bundleID
            );

        if (icon) {
            IARLog(@"applicationIconForBundleIdentifier: %@",
                   icon);

            return icon;
        }
    }

    IARLog(@"Could not obtain icon for %@",
           bundleID);

    return nil;
}

#pragma mark - Root folder

static id IARGetRootFolder(id manager) {

    SEL selector =
        NSSelectorFromString(@"rootFolder");

    return IARMsgSendID(manager, selector);
}

static BOOL IARRootContainsIcon(id rootFolder,
                                id icon) {

    if (!rootFolder || !icon)
        return NO;

    SEL selector =
        NSSelectorFromString(@"containsIcon:");

    if (![rootFolder respondsToSelector:selector])
        return NO;

    return ((BOOL (*)(id, SEL, id))objc_msgSend)(
        rootFolder,
        selector,
        icon
    );
}

#pragma mark - Icon state refresh

static void IARRefreshIconState(void) {

    IARLog(@"================================");
    IARLog(@"Starting icon state refresh");

    id controller =
        IARGetIconController();

    if (!controller)
        return;

    id manager =
        IARGetIconManager(controller);

    if (!manager)
        return;

    id model =
        IARGetIconModel(manager);

    if (!model)
        return;

    /*
     * These selectors vary between iOS versions.
     * We only call them when they actually exist.
     */

    NSArray *refreshSelectors = @[
        @"reloadIconState",
        @"reloadIconStateFromDisk",
        @"_reloadIconState",
        @"_reloadIconStateFromDisk",
        @"updateIconState",
        @"_updateIconState",
        @"rebuildIconState",
        @"_rebuildIconState"
    ];

    BOOL called = NO;

    for (NSString *name in refreshSelectors) {

        SEL selector =
            NSSelectorFromString(name);

        if ([model respondsToSelector:selector]) {

            IARLog(@"Calling model selector: %@",
                   name);

            IARMsgSendVoid(model, selector);

            called = YES;
            break;
        }
    }

    if (!called) {
        IARLog(@"No icon-model refresh selector found");
    }

    /*
     * Also ask SpringBoard / icon manager to update
     * if the corresponding method exists.
     */

    NSArray *managerSelectors = @[
        @"reloadIconState",
        @"_reloadIconState",
        @"updateIconState",
        @"_updateIconState"
    ];

    for (NSString *name in managerSelectors) {

        SEL selector =
            NSSelectorFromString(name);

        if ([manager respondsToSelector:selector]) {

            IARLog(@"Calling manager selector: %@",
                   name);

            IARMsgSendVoid(manager, selector);
            break;
        }
    }

    IARLog(@"Icon state refresh finished");
}

#pragma mark - Force insertion

static BOOL IARTryInsertIcon(id model,
                             id manager,
                             id controller,
                             id icon) {

    if (!icon)
        return NO;

    /*
     * Different iOS versions expose different insertion
     * methods. Check the actual runtime instead of assuming
     * a selector exists.
     */

    NSArray *targets = @[
        controller ?: [NSNull null],
        manager ?: [NSNull null],
        model ?: [NSNull null]
    ];

    NSArray *selectors = @[
        @"addNewIconToFirstAvailablePage:animate:",
        @"addIconToFirstAvailablePage:animate:",
        @"addIcon:toFirstAvailablePageWithAnimation:",
        @"addIconToFirstAvailablePage:"
    ];

    for (id target in targets) {

        if (target == [NSNull null])
            continue;

        for (NSString *name in selectors) {

            SEL selector =
                NSSelectorFromString(name);

            if (![target respondsToSelector:selector])
                continue;

            IARLog(@"FOUND insertion selector %@ on %@",
                   name,
                   NSStringFromClass(
                       [target class]
                   ));

            if ([name hasSuffix:@"animate:"]) {

                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                    target,
                    selector,
                    icon,
                    NO
                );

            } else {

                ((void (*)(id, SEL, id))objc_msgSend)(
                    target,
                    selector,
                    icon
                );
            }

            return YES;
        }
    }

    IARLog(@"No runtime insertion selector available");

    return NO;
}

#pragma mark - Process application

static void IARProcessBundleID(NSString *bundleID) {

    if (!bundleID.length)
        return;

    IARLog(@"================================");
    IARLog(@"PROCESSING %@", bundleID);

    id controller =
        IARGetIconController();

    if (!controller)
        return;

    id manager =
        IARGetIconManager(controller);

    if (!manager)
        return;

    id model =
        IARGetIconModel(manager);

    if (!model)
        return;

    id rootFolder =
        IARGetRootFolder(manager);

    id icon =
        IARGetIconForBundleID(
            model,
            bundleID
        );

    if (!icon) {
        IARLog(@"Icon unavailable yet");

        /*
         * TrollStore/LaunchServices may finish registering
         * the application slightly after it appears in the
         * application list.
         */
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(2.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                IARProcessBundleID(bundleID);
            }
        );

        return;
    }

    if (rootFolder &&
        IARRootContainsIcon(rootFolder, icon)) {

        IARLog(@"Icon is already on Home Screen");
        return;
    }

    IARLog(@"Icon is NOT on Home Screen");

    BOOL inserted =
        IARTryInsertIcon(
            model,
            manager,
            controller,
            icon
        );

    if (inserted) {

        IARLog(@"Icon insertion method executed");

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(0.5 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                IARRefreshIconState();
            }
        );

    } else {

        /*
         * On iOS versions where direct insertion isn't
         * exported, refresh the icon state and retry.
         */

        IARLog(@"Direct insertion unavailable");
        IARLog(@"Trying icon-state refresh");

        IARRefreshIconState();

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                id newController =
                    IARGetIconController();

                id newManager =
                    IARGetIconManager(newController);

                id newModel =
                    IARGetIconModel(newManager);

                id newIcon =
                    IARGetIconForBundleID(
                        newModel,
                        bundleID
                    );

                if (newIcon) {

                    IARLog(@"Retrying insertion");

                    if (IARTryInsertIcon(
                            newModel,
                            newManager,
                            newController,
                            newIcon)) {

                        IARLog(@"Retry succeeded");

                    } else {

                        IARLog(@"Retry failed");
                    }
                }
            }
        );
    }
}

#pragma mark - New application detection

static NSMutableSet *gKnownBundleIDs;

static void IARPoll(void) {

    NSArray *current =
        IARGetBundleIDs();

    if (!current)
        return;

    NSMutableSet *currentSet =
        [NSMutableSet setWithArray:current];

    if (!gKnownBundleIDs) {

        gKnownBundleIDs =
            [currentSet mutableCopy];

        IARLog(@"BASELINE: %lu applications",
               (unsigned long)gKnownBundleIDs.count);

        return;
    }

    NSMutableSet *newApps =
        [currentSet mutableCopy];

    [newApps minusSet:gKnownBundleIDs];

    if (newApps.count == 0) {

        IARLog(@"No new applications");

        gKnownBundleIDs =
            [currentSet mutableCopy];

        return;
    }

    IARLog(@"NEW APPLICATIONS: %lu",
           (unsigned long)newApps.count);

    for (NSString *bundleID in newApps) {

        IARLog(@"NEW BUNDLE ID: %@",
               bundleID);

        /*
         * Give LaunchServices/TrollStore a little time to
         * finish registering the icon before touching
         * SpringBoard's icon model.
         */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.5 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                IARProcessBundleID(bundleID);
            }
        );
    }

    gKnownBundleIDs =
        [currentSet mutableCopy];
}

#pragma mark - Constructor

%ctor {

    @autoreleasepool {

        IARLog(@"================================");
        IARLog(@"IconAutoRefresh loaded");
        IARLog(@"================================");

        /*
         * Wait until SpringBoard has completed startup.
         */
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(5.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{

                IARLog(@"Creating polling timer");

                dispatch_queue_t queue =
                    dispatch_queue_create(
                        "com.custom.iconautorefresh.poll",
                        DISPATCH_QUEUE_SERIAL
                    );

                dispatch_source_t timer =
                    dispatch_source_create(
                        DISPATCH_SOURCE_TYPE_TIMER,
                        0,
                        0,
                        queue
                    );

                if (!timer) {
                    IARLog(@"ERROR: timer creation failed");
                    return;
                }

                /*
                 * First poll after 1 second.
                 * Then every 3 seconds.
                 */
                dispatch_source_set_timer(
                    timer,
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(1.0 * NSEC_PER_SEC)
                    ),
                    (uint64_t)(3.0 * NSEC_PER_SEC),
                    (uint64_t)(0.5 * NSEC_PER_SEC)
                );

                dispatch_source_set_event_handler(
                    timer,
                    ^{

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                IARLog(@"Timer fired");
                                IARPoll();
                            }
                        );
                    }
                );

                dispatch_resume(timer);

                /*
                 * Keep the dispatch source alive.
                 */
                static dispatch_source_t sTimer;
                sTimer = timer;

                IARLog(@"Polling timer started successfully");
            }
        );
    }
}
