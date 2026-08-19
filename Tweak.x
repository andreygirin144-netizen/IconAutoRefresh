#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - Logging

static NSString *const kLogPath =
    @"/var/mobile/IconAutoRefresh.log";

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

    NSFileManager *fm =
        [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:kLogPath]) {
        [fm createFileAtPath:kLogPath
                    contents:nil
                  attributes:nil];
    }

    NSFileHandle *handle =
        [NSFileHandle fileHandleForWritingAtPath:kLogPath];

    if (handle) {
        [handle seekToEndOfFile];

        [handle writeData:
            [line dataUsingEncoding:NSUTF8StringEncoding]];

        [handle closeFile];
    }
}

#pragma mark - Private interfaces

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBIconModel : NSObject

- (SBIcon *)expectedIconForDisplayIdentifier:
    (NSString *)identifier;

- (SBIcon *)applicationIconForBundleIdentifier:
    (NSString *)identifier;

- (void)addIcon:(SBIcon *)icon;

- (void)saveIconState;

@end

@interface SBHIconManager : NSObject

- (SBIconModel *)iconModel;

- (id)rootFolder;

- (void)addNewIconsToDesignatedLocations:
    (NSArray *)icons
    saveIconState:(BOOL)save;

- (void)addNewIconToDesignatedLocation:
    (SBIcon *)icon
    options:(id)options;

- (id)bestHomeScreenLocationForIcon:
    (SBIcon *)icon;

- (id)bestLocationForIcon:
    (SBIcon *)icon;

@end

@interface SBIconController : NSObject

+ (instancetype)sharedInstance;

- (SBHIconManager *)iconManager;

@end

#pragma mark - Get installed applications

static NSArray *IARGetInstalledApplications(void) {

    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {
        IARLog(@"LSApplicationWorkspace not found");
        return nil;
    }

    SEL defaultSelector =
        NSSelectorFromString(@"defaultWorkspace");

    id workspace = nil;

    if ([workspaceClass respondsToSelector:defaultSelector]) {

        IMP imp =
            [workspaceClass methodForSelector:defaultSelector];

        id (*func)(id, SEL) =
            (id (*)(id, SEL))imp;

        workspace =
            func(workspaceClass, defaultSelector);
    }

    if (!workspace) {
        IARLog(@"defaultWorkspace = nil");
        return nil;
    }

    SEL appsSelector =
        NSSelectorFromString(
            @"allInstalledApplications"
        );

    if (![workspace respondsToSelector:appsSelector]) {
        IARLog(@"allInstalledApplications unavailable");
        return nil;
    }

    IMP imp =
        [workspace methodForSelector:appsSelector];

    NSArray *(*func)(id, SEL) =
        (NSArray *(*)(id, SEL))imp;

    NSArray *applications =
        func(workspace, appsSelector);

    IARLog(@"LaunchServices returned %lu applications",
           (unsigned long)applications.count);

    return applications;
}

static NSArray *IARGetBundleIDs(void) {

    NSArray *applications =
        IARGetInstalledApplications();

    if (!applications) {
        return nil;
    }

    NSMutableArray *result =
        [NSMutableArray array];

    for (id application in applications) {

        NSString *bundleID = nil;

        SEL selector =
            NSSelectorFromString(@"bundleIdentifier");

        if ([application respondsToSelector:selector]) {

            IMP imp =
                [application methodForSelector:selector];

            NSString *(*func)(id, SEL) =
                (NSString *(*)(id, SEL))imp;

            bundleID =
                func(application, selector);
        }

        if (!bundleID) {

            selector =
                NSSelectorFromString(
                    @"applicationIdentifier"
                );

            if ([application respondsToSelector:selector]) {

                IMP imp =
                    [application methodForSelector:selector];

                NSString *(*func)(id, SEL) =
                    (NSString *(*)(id, SEL))imp;

                bundleID =
                    func(application, selector);
            }
        }

        if (bundleID) {
            [result addObject:bundleID];
        }
    }

    return result;
}

#pragma mark - Add icon

static void IARAddIconForBundleID(
    NSString *bundleID
) {

    IARLog(@"");
    IARLog(@"================================");
    IARLog(@"ADDING ICON");
    IARLog(@"Bundle ID: %@", bundleID);
    IARLog(@"================================");

    Class controllerClass =
        NSClassFromString(@"SBIconController");

    if (!controllerClass) {
        IARLog(@"SBIconController not found");
        return;
    }

    SEL sharedSelector =
        NSSelectorFromString(@"sharedInstance");

    if (![controllerClass
          respondsToSelector:sharedSelector]) {

        IARLog(@"sharedInstance unavailable");
        return;
    }

    IMP sharedIMP =
        [controllerClass
         methodForSelector:sharedSelector];

    id (*sharedFunc)(id, SEL) =
        (id (*)(id, SEL))sharedIMP;

    SBIconController *controller =
        sharedFunc(controllerClass,
                   sharedSelector);

    if (!controller) {
        IARLog(@"SBIconController = nil");
        return;
    }

    SBHIconManager *manager = nil;

    SEL managerSelector =
        NSSelectorFromString(@"iconManager");

    if ([controller
         respondsToSelector:managerSelector]) {

        IMP imp =
            [controller methodForSelector:
                managerSelector];

        id (*func)(id, SEL) =
            (id (*)(id, SEL))imp;

        manager =
            func(controller,
                 managerSelector);
    }

    if (!manager) {
        IARLog(@"SBHIconManager = nil");
        return;
    }

    IARLog(@"SBHIconManager = %@", manager);

    SBIconModel *model = nil;

    SEL modelSelector =
        NSSelectorFromString(@"iconModel");

    if ([manager respondsToSelector:modelSelector]) {

        IMP imp =
            [manager methodForSelector:modelSelector];

        id (*func)(id, SEL) =
            (id (*)(id, SEL))imp;

        model =
            func(manager,
                 modelSelector);
    }

    if (!model) {
        IARLog(@"SBIconModel = nil");
        return;
    }

    IARLog(@"SBIconModel = %@", model);

    SBIcon *icon = nil;

    /*
     * First try expectedIconForDisplayIdentifier:
     */

    SEL expectedSelector =
        NSSelectorFromString(
            @"expectedIconForDisplayIdentifier:"
        );

    if ([model respondsToSelector:expectedSelector]) {

        IMP imp =
            [model methodForSelector:expectedSelector];

        id (*func)(id, SEL, NSString *) =
            (id (*)(id, SEL, NSString *))imp;

        icon =
            func(model,
                 expectedSelector,
                 bundleID);

        IARLog(
            @"expectedIconForDisplayIdentifier = %@",
            icon
        );
    }

    /*
     * Fallback.
     */

    if (!icon) {

        SEL applicationSelector =
            NSSelectorFromString(
                @"applicationIconForBundleIdentifier:"
            );

        if ([model respondsToSelector:
                applicationSelector]) {

            IMP imp =
                [model methodForSelector:
                    applicationSelector];

            id (*func)(id, SEL, NSString *) =
                (id (*)(id, SEL, NSString *))imp;

            icon =
                func(model,
                     applicationSelector,
                     bundleID);

            IARLog(
                @"applicationIconForBundleIdentifier = %@",
                icon
            );
        }
    }

    if (!icon) {
        IARLog(@"FAILED: could not obtain SBIcon");
        return;
    }

    if ([icon respondsToSelector:
            @selector(applicationBundleID)]) {

        IARLog(
            @"Icon bundle ID = %@",
            [icon applicationBundleID]
        );
    }

    /*
     * Check whether it is already in root folder.
     */

    id rootFolder = nil;

    SEL rootSelector =
        NSSelectorFromString(@"rootFolder");

    if ([manager respondsToSelector:rootSelector]) {

        IMP imp =
            [manager methodForSelector:rootSelector];

        id (*func)(id, SEL) =
            (id (*)(id, SEL))imp;

        rootFolder =
            func(manager,
                 rootSelector);
    }

    if (rootFolder &&
        [rootFolder respondsToSelector:
            NSSelectorFromString(@"containsIcon:")]) {

        SEL containsSelector =
            NSSelectorFromString(@"containsIcon:");

        IMP imp =
            [rootFolder methodForSelector:
                containsSelector];

        BOOL (*func)(id, SEL, id) =
            (BOOL (*)(id, SEL, id))imp;

        BOOL contains =
            func(rootFolder,
                 containsSelector,
                 icon);

        IARLog(
            @"rootFolder containsIcon = %d",
            contains
        );

        if (contains) {
            IARLog(@"Icon already on Home Screen");
            return;
        }
    }

    /*
     * IMPORTANT:
     *
     * iOS 17.7.1 has this method:
     *
     * addNewIconsToDesignatedLocations:saveIconState:
     *
     * This is the method we want to test.
     */

    SEL addSelector =
        NSSelectorFromString(
            @"addNewIconsToDesignatedLocations:saveIconState:"
        );

    if ([manager respondsToSelector:addSelector]) {

        IARLog(
            @"FOUND addNewIconsToDesignatedLocations:saveIconState:"
        );

        NSArray *icons =
            @[ icon ];

        IMP imp =
            [manager methodForSelector:addSelector];

        void (*func)(id, SEL, NSArray *, BOOL) =
            (void (*)(id, SEL, NSArray *, BOOL))imp;

        IARLog(@"Calling addNewIconsToDesignatedLocations:");

        func(manager,
             addSelector,
             icons,
             YES);

        IARLog(
            @"addNewIconsToDesignatedLocations completed"
        );

        /*
         * Give SpringBoard a moment to process
         * the model mutation.
         */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{

                IARLog(
                    @"Checking icon after insertion..."
                );

                if (rootFolder &&
                    [rootFolder respondsToSelector:
                        NSSelectorFromString(
                            @"containsIcon:"
                        )]) {

                    SEL containsSelector =
                        NSSelectorFromString(
                            @"containsIcon:"
                        );

                    IMP containsIMP =
                        [rootFolder methodForSelector:
                            containsSelector];

                    BOOL (*containsFunc)(
                        id,
                        SEL,
                        id
                    ) =
                        (BOOL (*)(id, SEL, id))
                        containsIMP;

                    BOOL result =
                        containsFunc(
                            rootFolder,
                            containsSelector,
                            icon
                        );

                    IARLog(
                        @"AFTER INSERT rootFolder containsIcon = %d",
                        result
                    );
                }

                IARLog(@"Icon insertion test finished");
            }
        );

        return;
    }

    IARLog(
        @"ERROR: addNewIconsToDesignatedLocations unavailable"
    );

    /*
     * Secondary diagnostic only.
     */

    SEL addOneSelector =
        NSSelectorFromString(
            @"addNewIconToDesignatedLocation:options:"
        );

    if ([manager respondsToSelector:addOneSelector]) {

        IARLog(
            @"FOUND addNewIconToDesignatedLocation:options:"
        );

        IARLog(
            @"NOT calling secondary method yet"
        );
    }

    /*
     * Last resort: model addIcon:
     *
     * We deliberately don't call it yet because the
     * manager method above is the safer candidate.
     */

    if ([model respondsToSelector:
            NSSelectorFromString(@"addIcon:")]) {

        IARLog(@"SBIconModel addIcon: is available");
    }
}

#pragma mark - Polling

static NSMutableSet *gKnownBundleIDs;

static void IARPoll(void) {

    NSArray *current =
        IARGetBundleIDs();

    if (!current) {
        return;
    }

    NSMutableSet *currentSet =
        [NSMutableSet setWithArray:current];

    if (!gKnownBundleIDs) {

        gKnownBundleIDs =
            [currentSet mutableCopy];

        IARLog(
            @"BASELINE: %lu applications",
            (unsigned long)gKnownBundleIDs.count
        );

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
         * Wait a little after LaunchServices sees
         * the application so SpringBoard has time to
         * create the application icon.
         */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                IARAddIconForBundleID(bundleID);
            }
        );
    }

    gKnownBundleIDs =
        [currentSet mutableCopy];
}

#pragma mark - Constructor

%ctor {

    IARLog(@"");
    IARLog(@"================================");
    IARLog(@"IconAutoRefresh loaded");
    IARLog(@"================================");

    /*
     * Wait for SpringBoard initialization.
     */

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(5 * NSEC_PER_SEC)
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

            dispatch_source_set_timer(
                timer,
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    1 * NSEC_PER_SEC
                ),
                3 * NSEC_PER_SEC,
                500 * NSEC_PER_MSEC
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

            IARLog(
                @"Polling timer started successfully"
            );
        }
    );
}
