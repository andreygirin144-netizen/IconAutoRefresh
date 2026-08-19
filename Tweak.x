#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

#pragma mark - Logging

static NSString *const kIARLogPath = @"/var/mobile/IconAutoRefresh.log";

static void IARLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSLog(@"[IconAutoRefresh] %@", message);

    NSString *timestamp =
        [NSDateFormatter localizedStringFromDate:[NSDate date]
                                         dateStyle:NSDateFormatterShortStyle
                                         timeStyle:NSDateFormatterMediumStyle];

    NSString *line =
        [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

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

        NSData *data =
            [line dataUsingEncoding:NSUTF8StringEncoding];

        [handle writeData:data];
        [handle closeFile];
    }
}

#pragma mark - Private interfaces

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBFolder : NSObject
- (BOOL)containsIcon:(id)icon;
@end

@interface SBRootFolder : SBFolder
@end

@interface SBHIconModel : NSObject

- (SBIcon *)expectedIconForDisplayIdentifier:(NSString *)identifier;
- (SBIcon *)applicationIconForBundleIdentifier:(NSString *)identifier;
- (SBIcon *)addApplicationIconForBundleIdentifier:(NSString *)identifier;

- (void)saveIconState;

@end

@interface SBHIconManager : NSObject

- (SBHIconModel *)iconModel;
- (SBRootFolder *)rootFolder;

- (void)addNewIconToFirstAvailablePage:(SBIcon *)icon
                               animate:(BOOL)animate;

@end

@interface SBIconController : UIViewController

+ (instancetype)sharedInstance;

- (SBHIconManager *)iconManager;

- (void)addNewIconToFirstAvailablePage:(SBIcon *)icon
                               animate:(BOOL)animate;

@end

#pragma mark - LaunchServices

static NSArray *IARGetInstalledApplications(void) {

    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {
        IARLog(@"LSApplicationWorkspace class not found");
        return nil;
    }

    id workspace = nil;

    SEL defaultWorkspace =
        NSSelectorFromString(@"defaultWorkspace");

    if ([workspaceClass respondsToSelector:defaultWorkspace]) {
        workspace =
            ((id (*)(id, SEL))objc_msgSend)
            (workspaceClass, defaultWorkspace);
    }

    if (!workspace) {
        IARLog(@"defaultWorkspace returned nil");
        return nil;
    }

    SEL allInstalled =
        NSSelectorFromString(@"allInstalledApplications");

    if (![workspace respondsToSelector:allInstalled]) {
        IARLog(@"allInstalledApplications unavailable");
        return nil;
    }

    NSArray *applications =
        ((id (*)(id, SEL))objc_msgSend)
        (workspace, allInstalled);

    if (!applications) {
        IARLog(@"allInstalledApplications returned nil");
        return nil;
    }

    return applications;
}

static NSString *IARBundleIdentifierForApplication(id application) {

    if (!application)
        return nil;

    SEL bundleIdentifier =
        NSSelectorFromString(@"bundleIdentifier");

    if ([application respondsToSelector:bundleIdentifier]) {

        return ((id (*)(id, SEL))objc_msgSend)
            (application, bundleIdentifier);
    }

    SEL applicationIdentifier =
        NSSelectorFromString(@"applicationIdentifier");

    if ([application respondsToSelector:applicationIdentifier]) {

        return ((id (*)(id, SEL))objc_msgSend)
            (application, applicationIdentifier);
    }

    return nil;
}

static NSSet<NSString *> *IARGetInstalledBundleIDs(void) {

    NSArray *applications =
        IARGetInstalledApplications();

    if (!applications)
        return nil;

    NSMutableSet *result =
        [NSMutableSet set];

    for (id application in applications) {

        NSString *bundleID =
            IARBundleIdentifierForApplication(application);

        if (bundleID.length > 0) {
            [result addObject:bundleID];
        }
    }

    return result;
}

#pragma mark - Add icon

static void IARAddApplicationToHomeScreen(NSString *bundleID) {

    if (![NSThread isMainThread]) {

        dispatch_async(dispatch_get_main_queue(), ^{
            IARAddApplicationToHomeScreen(bundleID);
        });

        return;
    }

    IARLog(@"--------------------------------");
    IARLog(@"Processing %@", bundleID);

    Class controllerClass =
        NSClassFromString(@"SBIconController");

    if (!controllerClass) {
        IARLog(@"SBIconController not found");
        return;
    }

    SBIconController *controller =
        [controllerClass sharedInstance];

    if (!controller) {
        IARLog(@"SBIconController sharedInstance = nil");
        return;
    }

    if (![controller respondsToSelector:@selector(iconManager)]) {
        IARLog(@"iconManager selector unavailable");
        return;
    }

    SBHIconManager *iconManager =
        [controller iconManager];

    if (!iconManager) {
        IARLog(@"iconManager = nil");
        return;
    }

    SBHIconModel *model = nil;

    if ([iconManager respondsToSelector:@selector(iconModel)]) {
        model = [iconManager iconModel];
    }

    if (!model) {
        IARLog(@"iconModel = nil");
        return;
    }

    SBRootFolder *rootFolder = nil;

    if ([iconManager respondsToSelector:@selector(rootFolder)]) {
        rootFolder = [iconManager rootFolder];
    }

    if (!rootFolder) {
        IARLog(@"rootFolder = nil");
    }

    /*
     * First try to get an already existing icon.
     */

    SBIcon *icon = nil;

    SEL expectedSelector =
        NSSelectorFromString(
            @"expectedIconForDisplayIdentifier:"
        );

    if ([model respondsToSelector:expectedSelector]) {

        icon =
            ((id (*)(id, SEL, id))objc_msgSend)
            (model,
             expectedSelector,
             bundleID);

        if (icon) {
            IARLog(@"Found icon using expectedIconForDisplayIdentifier");
        }
    }

    /*
     * Second method.
     */

    if (!icon) {

        SEL applicationIconSelector =
            NSSelectorFromString(
                @"applicationIconForBundleIdentifier:"
            );

        if ([model respondsToSelector:applicationIconSelector]) {

            icon =
                ((id (*)(id, SEL, id))objc_msgSend)
                (model,
                 applicationIconSelector,
                 bundleID);

            if (icon) {
                IARLog(@"Found icon using applicationIconForBundleIdentifier");
            }
        }
    }

    /*
     * If the icon does not exist in the icon model,
     * ask SpringBoard to create/register it.
     */

    if (!icon) {

        SEL addSelector =
            NSSelectorFromString(
                @"addApplicationIconForBundleIdentifier:"
            );

        if ([model respondsToSelector:addSelector]) {

            IARLog(@"Trying addApplicationIconForBundleIdentifier");

            icon =
                ((id (*)(id, SEL, id))objc_msgSend)
                (model,
                 addSelector,
                 bundleID);

            if (icon) {
                IARLog(@"Icon successfully created");
            }
        }
    }

    if (!icon) {
        IARLog(@"FAILED: could not obtain SBIcon for %@", bundleID);
        return;
    }

    /*
     * Check whether icon is already present.
     */

    BOOL alreadyOnHomeScreen = NO;

    if (rootFolder &&
        [rootFolder respondsToSelector:@selector(containsIcon:)]) {

        alreadyOnHomeScreen =
            [rootFolder containsIcon:icon];
    }

    IARLog(@"Icon = %@", icon);
    IARLog(@"Already on Home Screen = %d",
           alreadyOnHomeScreen);

    if (alreadyOnHomeScreen) {

        IARLog(@"Nothing to do: icon already exists");

        if ([model respondsToSelector:@selector(saveIconState)]) {
            [model saveIconState];
        }

        return;
    }

    /*
     * Add icon to Home Screen.
     */

    BOOL added = NO;

    SEL controllerAdd =
        NSSelectorFromString(
            @"addNewIconToFirstAvailablePage:animate:"
        );

    if ([controller respondsToSelector:controllerAdd]) {

        IARLog(@"Adding icon through SBIconController");

        ((void (*)(id, SEL, id, BOOL))objc_msgSend)
            (controller,
             controllerAdd,
             icon,
             NO);

        added = YES;
    }

    /*
     * Fallback to SBHIconManager.
     */

    if (!added &&
        [iconManager respondsToSelector:controllerAdd]) {

        IARLog(@"Adding icon through SBHIconManager");

        ((void (*)(id, SEL, id, BOOL))objc_msgSend)
            (iconManager,
             controllerAdd,
             icon,
             NO);

        added = YES;
    }

    if (!added) {

        IARLog(@"FAILED: no method available to add icon");

        return;
    }

    /*
     * Save icon state.
     */

    if ([model respondsToSelector:@selector(saveIconState)]) {

        IARLog(@"Saving icon state");

        [model saveIconState];
    }

    /*
     * Give SpringBoard a moment and check again.
     */

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{

            BOOL nowOnHomeScreen = NO;

            if (rootFolder &&
                [rootFolder respondsToSelector:@selector(containsIcon:)]) {

                nowOnHomeScreen =
                    [rootFolder containsIcon:icon];
            }

            IARLog(@"Post-add Home Screen check = %d",
                   nowOnHomeScreen);

            if (!nowOnHomeScreen) {
                IARLog(@"WARNING: icon was not added to rootFolder");
            } else {
                IARLog(@"SUCCESS: icon is now on Home Screen");
            }
        }
    );
}

#pragma mark - Polling

static NSMutableSet<NSString *> *gKnownBundleIDs;

static void IARCheckForNewApplications(void) {

    /*
     * LSApplicationWorkspace should not be queried from
     * an arbitrary background thread.
     *
     * Keep this entire operation on SpringBoard's main queue.
     */

    if (![NSThread isMainThread]) {

        dispatch_async(dispatch_get_main_queue(), ^{
            IARCheckForNewApplications();
        });

        return;
    }

    NSSet<NSString *> *current =
        IARGetInstalledBundleIDs();

    if (!current) {
        IARLog(@"Poll: unable to obtain installed applications");
        return;
    }

    /*
     * First invocation establishes baseline.
     */

    if (!gKnownBundleIDs) {

        gKnownBundleIDs =
            [current mutableCopy];

        IARLog(
            @"Poll baseline captured: %lu applications",
            (unsigned long)gKnownBundleIDs.count
        );

        return;
    }

    NSMutableSet<NSString *> *newApplications =
        [current mutableCopy];

    [newApplications minusSet:gKnownBundleIDs];

    /*
     * Update snapshot immediately.
     */

    gKnownBundleIDs =
        [current mutableCopy];

    if (newApplications.count == 0) {
        return;
    }

    IARLog(
        @"Poll detected %lu NEW application(s)",
        (unsigned long)newApplications.count
    );

    for (NSString *bundleID in newApplications) {

        IARLog(@"New application: %@", bundleID);

        /*
         * Give LaunchServices / SpringBoard a short moment
         * to finish registering the application.
         */

        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{

                IARAddApplicationToHomeScreen(bundleID);
            }
        );
    }
}

#pragma mark - Timer

static void IARStartPolling(void) {

    dispatch_queue_t queue =
        dispatch_get_main_queue();

    dispatch_source_t timer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            queue
        );

    if (!timer) {
        IARLog(@"Failed to create polling timer");
        return;
    }

    /*
     * First check after 5 seconds.
     * Then every 3 seconds.
     */

    dispatch_source_set_timer(
        timer,
        dispatch_time(
            DISPATCH_TIME_NOW,
            5 * NSEC_PER_SEC
        ),
        3 * NSEC_PER_SEC,
        500 * NSEC_PER_MSEC
    );

    dispatch_source_set_event_handler(timer, ^{

        IARCheckForNewApplications();

    });

    /*
     * Keep the timer alive for the lifetime of SpringBoard.
     */

    dispatch_resume(timer);

    IARLog(@"Polling started");
}

#pragma mark - Constructor

%ctor {

    @autoreleasepool {

        IARLog(@"================================");
        IARLog(@"IconAutoRefresh loaded");
        IARLog(@"Starting application monitor");

        /*
         * Start on SpringBoard main queue.
         */

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                IARStartPolling();

            }
        );

        IARLog(@"Initialization complete");
    }

    %init;
}
