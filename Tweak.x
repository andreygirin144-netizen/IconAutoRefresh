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

        NSData *data =
            [line dataUsingEncoding:NSUTF8StringEncoding];

        [handle writeData:data];
        [handle closeFile];
    }
}

#pragma mark - Private classes

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBRootFolder : NSObject
- (BOOL)containsIcon:(id)icon;
@end

@interface SBIconModel : NSObject
- (id)expectedIconForDisplayIdentifier:(NSString *)identifier;
- (id)applicationIconForBundleIdentifier:(NSString *)identifier;
- (id)addApplicationIconForBundleIdentifier:(NSString *)identifier;
@end

@interface SBHIconManager : NSObject
- (SBIconModel *)iconModel;
- (SBRootFolder *)rootFolder;
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
@end

#pragma mark - Globals

static NSMutableSet<NSString *> *gKnownBundleIDs;
static dispatch_source_t gPollTimer;

#pragma mark - LaunchServices

static NSArray<NSString *> *IARGetInstalledBundleIDs(void) {

    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {
        IARLog(@"LSApplicationWorkspace not found");
        return nil;
    }

    id workspace = nil;

    SEL defaultWorkspace =
        NSSelectorFromString(@"defaultWorkspace");

    if ([workspaceClass respondsToSelector:defaultWorkspace]) {

        id (*msgSend)(id, SEL) =
            (id (*)(id, SEL))objc_msgSend;

        workspace =
            msgSend(workspaceClass, defaultWorkspace);
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

    NSArray *applications = nil;

    NSArray *(*msgSendArray)(id, SEL) =
        (NSArray *(*)(id, SEL))objc_msgSend;

    applications =
        msgSendArray(workspace, allInstalled);

    if (!applications) {
        IARLog(@"LaunchServices returned nil");
        return nil;
    }

    NSMutableArray *result =
        [NSMutableArray array];

    for (id app in applications) {

        NSString *bundleID = nil;

        SEL bundleIdentifier =
            NSSelectorFromString(@"bundleIdentifier");

        if ([app respondsToSelector:bundleIdentifier]) {

            NSString *(*getString)(id, SEL) =
                (NSString *(*)(id, SEL))objc_msgSend;

            bundleID =
                getString(app, bundleIdentifier);
        }

        if (bundleID.length > 0) {
            [result addObject:bundleID];
        }
    }

    IARLog(@"LaunchServices returned %lu applications",
           (unsigned long)result.count);

    return result;
}

#pragma mark - Add icon

static BOOL IARAddIconForBundleID(NSString *bundleID) {

    if (bundleID.length == 0) {
        return NO;
    }

    IARLog(@"--------------------------------");
    IARLog(@"Trying to add icon: %@", bundleID);

    Class controllerClass =
        NSClassFromString(@"SBIconController");

    if (!controllerClass) {
        IARLog(@"SBIconController not found");
        return NO;
    }

    SBIconController *controller =
        [controllerClass sharedInstance];

    if (!controller) {
        IARLog(@"SBIconController sharedInstance = nil");
        return NO;
    }

    SBHIconManager *manager = nil;

    SEL iconManagerSelector =
        NSSelectorFromString(@"iconManager");

    if ([controller respondsToSelector:iconManagerSelector]) {

        SBHIconManager *(*getManager)(id, SEL) =
            (SBHIconManager *(*)(id, SEL))objc_msgSend;

        manager =
            getManager(controller, iconManagerSelector);
    }

    if (!manager) {
        IARLog(@"SBHIconManager unavailable");
        return NO;
    }

    SBIconModel *model = nil;

    SEL modelSelector =
        NSSelectorFromString(@"iconModel");

    if ([manager respondsToSelector:modelSelector]) {

        SBIconModel *(*getModel)(id, SEL) =
            (SBIconModel *(*)(id, SEL))objc_msgSend;

        model =
            getModel(manager, modelSelector);
    }

    if (!model) {
        IARLog(@"SBIconModel unavailable");
        return NO;
    }

    id icon = nil;

    /*
     * First try expectedIconForDisplayIdentifier:
     */

    SEL expectedSelector =
        NSSelectorFromString(
            @"expectedIconForDisplayIdentifier:");

    if ([model respondsToSelector:expectedSelector]) {

        id (*getIcon)(id, SEL, NSString *) =
            (id (*)(id, SEL, NSString *))objc_msgSend;

        icon =
            getIcon(model,
                    expectedSelector,
                    bundleID);

        IARLog(@"expectedIcon = %@", icon);
    }

    /*
     * Fallback.
     */

    if (!icon) {

        SEL applicationSelector =
            NSSelectorFromString(
                @"applicationIconForBundleIdentifier:");

        if ([model respondsToSelector:applicationSelector]) {

            id (*getIcon)(id, SEL, NSString *) =
                (id (*)(id, SEL, NSString *))objc_msgSend;

            icon =
                getIcon(model,
                        applicationSelector,
                        bundleID);

            IARLog(@"applicationIcon = %@", icon);
        }
    }

    if (!icon) {

        SEL addSelector =
            NSSelectorFromString(
                @"addApplicationIconForBundleIdentifier:");

        if ([model respondsToSelector:addSelector]) {

            id (*addIcon)(id, SEL, NSString *) =
                (id (*)(id, SEL, NSString *))objc_msgSend;

            icon =
                addIcon(model,
                        addSelector,
                        bundleID);

            IARLog(@"addApplicationIcon = %@", icon);
        }
    }

    if (!icon) {
        IARLog(@"FAILED: could not obtain SBIcon");
        return NO;
    }

    IARLog(@"SBIcon obtained: %@", icon);

    /*
     * Check root folder.
     */

    SBRootFolder *rootFolder = nil;

    SEL rootSelector =
        NSSelectorFromString(@"rootFolder");

    if ([manager respondsToSelector:rootSelector]) {

        SBRootFolder *(*getRoot)(id, SEL) =
            (SBRootFolder *(*)(id, SEL))objc_msgSend;

        rootFolder =
            getRoot(manager, rootSelector);
    }

    if (!rootFolder) {
        IARLog(@"SBRootFolder unavailable");
        return NO;
    }

    BOOL alreadyOnHomeScreen = NO;

    SEL containsSelector =
        NSSelectorFromString(@"containsIcon:");

    if ([rootFolder respondsToSelector:containsSelector]) {

        BOOL (*contains)(id, SEL, id) =
            (BOOL (*)(id, SEL, id))objc_msgSend;

        alreadyOnHomeScreen =
            contains(rootFolder,
                     containsSelector,
                     icon);
    }

    IARLog(@"containsIcon = %d",
           alreadyOnHomeScreen);

    if (alreadyOnHomeScreen) {
        IARLog(@"Icon already on Home Screen");
        return YES;
    }

    /*
     * IMPORTANT:
     *
     * Your previous log showed that the old
     * addNewIconToFirstAvailablePage:animate:
     * selector DOES NOT exist on iOS 17.7.1.
     *
     * Therefore don't call it blindly.
     *
     * Try the icon model's insertion methods instead.
     */

    SEL addToFirstPage =
        NSSelectorFromString(
            @"addIcon:toFirstAvailablePage:");

    if ([model respondsToSelector:addToFirstPage]) {

        void (*call)(id, SEL, id, BOOL) =
            (void (*)(id, SEL, id, BOOL))objc_msgSend;

        call(model,
             addToFirstPage,
             icon,
             YES);

        IARLog(@"Called addIcon:toFirstAvailablePage:");

        return YES;
    }

    /*
     * Another possible private API.
     */

    SEL placeSelector =
        NSSelectorFromString(
            @"placeIcon:inRootFolder:");

    if ([model respondsToSelector:placeSelector]) {

        void (*call)(id, SEL, id, id) =
            (void (*)(id, SEL, id, id))objc_msgSend;

        call(model,
             placeSelector,
             icon,
             rootFolder);

        IARLog(@"Called placeIcon:inRootFolder:");

        return YES;
    }

    IARLog(@"NO SUPPORTED ICON INSERTION METHOD FOUND");

    /*
     * Don't pretend success.
     */

    return NO;
}

#pragma mark - Delayed processing

static void IARProcessNewApplication(NSString *bundleID) {

    if (bundleID.length == 0) {
        return;
    }

    /*
     * TrollStore Lite can register the application first,
     * while SpringBoard's icon model becomes ready slightly later.
     *
     * Retry several times.
     */

    NSArray<NSNumber *> *delays = @[
        @1,
        @3,
        @6,
        @10
    ];

    for (NSNumber *delayNumber in delays) {

        NSTimeInterval delay =
            delayNumber.doubleValue;

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(delay *
                          NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{

                IARLog(@"Retry %.0fs for %@",
                       delay,
                       bundleID);

                IARAddIconForBundleID(bundleID);
            }
        );
    }
}

#pragma mark - Poll

static void IARPoll(void) {

    @autoreleasepool {

        IARLog(@"========== POLL ==========");

        NSArray<NSString *> *current =
            IARGetInstalledBundleIDs();

        if (!current) {
            IARLog(@"Could not enumerate applications");
            return;
        }

        NSSet *currentSet =
            [NSSet setWithArray:current];

        if (!gKnownBundleIDs) {

            gKnownBundleIDs =
                [NSMutableSet setWithSet:currentSet];

            IARLog(@"BASELINE: %lu applications",
                   (unsigned long)gKnownBundleIDs.count);

            return;
        }

        NSMutableSet *newApplications =
            [currentSet mutableCopy];

        [newApplications
            minusSet:gKnownBundleIDs];

        if (newApplications.count == 0) {

            IARLog(@"No new applications");

        } else {

            IARLog(@"NEW APPLICATIONS: %lu",
                   (unsigned long)newApplications.count);

            for (NSString *bundleID
                 in newApplications) {

                IARLog(@"NEW BUNDLE ID: %@",
                       bundleID);

                IARProcessNewApplication(bundleID);
            }
        }

        gKnownBundleIDs =
            [NSMutableSet setWithSet:currentSet];
    }
}

#pragma mark - Start timer

static void IARStartPolling(void) {

    IARLog(@"Creating polling timer");

    if (gPollTimer) {
        IARLog(@"Polling timer already exists");
        return;
    }

    dispatch_queue_t queue =
        dispatch_get_main_queue();

    gPollTimer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            queue);

    if (!gPollTimer) {
        IARLog(@"FAILED to create timer");
        return;
    }

    dispatch_source_set_timer(
        gPollTimer,
        dispatch_time(
            DISPATCH_TIME_NOW,
            2 * NSEC_PER_SEC),
        3 * NSEC_PER_SEC,
        500 * NSEC_PER_MSEC
    );

    dispatch_source_set_event_handler(
        gPollTimer,
        ^{
            IARLog(@"Timer fired");
            IARPoll();
        }
    );

    dispatch_resume(gPollTimer);

    IARLog(@"Polling timer started successfully");
}

#pragma mark - Constructor

%ctor {

    @autoreleasepool {

        IARLog(@"");
        IARLog(@"================================");
        IARLog(@"IconAutoRefresh loaded");
        IARLog(@"================================");

        /*
         * Wait until SpringBoard has finished
         * initializing its icon model.
         */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                3 * NSEC_PER_SEC),
            dispatch_get_main_queue(),
            ^{
                IARStartPolling();
            }
        );
    }
}
