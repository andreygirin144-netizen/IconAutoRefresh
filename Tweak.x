#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - Logging

static NSString * const kIARLogPath = @"/var/mobile/IconAutoRefresh.log";

static void IARLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSLog(@"[IconAutoRefresh] %@", message);

    NSString *line =
        [NSString stringWithFormat:@"[%@] %@\n",
         [NSDate date], message];

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

#pragma mark - Private interfaces

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBFolder : NSObject
- (BOOL)containsIcon:(id)icon;
@end

@interface SBRootFolder : SBFolder
@end

@interface SBIconModel : NSObject
- (SBIcon *)expectedIconForDisplayIdentifier:(NSString *)identifier;
- (SBIcon *)applicationIconForBundleIdentifier:(NSString *)identifier;
- (void)addNewIconsToDesignatedLocations:(NSArray *)icons
                           saveIconState:(BOOL)save;
- (void)saveIconState;
@end

@interface SBHIconManager : NSObject
- (SBIconModel *)iconModel;
- (SBRootFolder *)rootFolder;
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
@end

#pragma mark - Runtime helpers

static void IARCallVoid(id object, SEL selector) {
    if (!object || !selector) {
        return;
    }

    if (![object respondsToSelector:selector]) {
        return;
    }

    ((void (*)(id, SEL))objc_msgSend)(object, selector);
}

static void IARCallVoidBool(id object, SEL selector, BOOL value) {
    if (!object || !selector) {
        return;
    }

    if (![object respondsToSelector:selector]) {
        return;
    }

    ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
}

#pragma mark - Refresh Home Screen

static void IARRefreshHomeScreen(void) {

    IARLog(@"--------------------------------");
    IARLog(@"BEGIN UI REFRESH");

    Class rootViewClass =
        NSClassFromString(@"SBRootFolderView");

    Class iconListViewClass =
        NSClassFromString(@"SBIconListView");

    Class rootFolderControllerClass =
        NSClassFromString(@"SBRootFolderController");

    IARLog(@"SBRootFolderView = %@", rootViewClass);
    IARLog(@"SBIconListView = %@", iconListViewClass);
    IARLog(@"SBRootFolderController = %@", rootFolderControllerClass);

    /*
     * We intentionally try several known-style refresh methods.
     * Every call is protected by respondsToSelector:, so an unavailable
     * private method is simply skipped.
     */

    NSArray *rootViewMethods = @[
        @"reload",
        @"reloadIcons",
        @"reloadIconViews",
        @"updateIconViews",
        @"updateIcons",
        @"layoutSubviews",
        @"setNeedsLayout",
        @"layoutIfNeeded"
    ];

    NSArray *iconListMethods = @[
        @"reload",
        @"reloadIcons",
        @"reloadIconViews",
        @"updateIconViews",
        @"updateIcons",
        @"layoutSubviews",
        @"setNeedsLayout",
        @"layoutIfNeeded"
    ];

    /*
     * Find the current root folder view through SBIconController.
     */

    SBIconController *controller =
        [NSClassFromString(@"SBIconController") sharedInstance];

    if (!controller) {
        IARLog(@"UI refresh: SBIconController unavailable");
        return;
    }

    IARLog(@"UI refresh: controller = %@", controller);

    /*
     * Traverse controller's view hierarchy.
     */

    UIView *controllerView = nil;

    if ([controller isKindOfClass:[UIViewController class]]) {
        controllerView =
            [(UIViewController *)controller view];
    }

    if (!controllerView) {
        IARLog(@"UI refresh: controller view unavailable");
        return;
    }

    NSMutableArray *views =
        [NSMutableArray arrayWithObject:controllerView];

    while (views.count > 0) {

        UIView *view = views.firstObject;
        [views removeObjectAtIndex:0];

        Class cls = [view class];

        NSString *className =
            NSStringFromClass(cls);

        BOOL isRootView =
            [className isEqualToString:@"SBRootFolderView"];

        BOOL isIconListView =
            [className isEqualToString:@"SBIconListView"];

        if (isRootView || isIconListView) {

            IARLog(@"Found icon view: %@", className);

            NSArray *methods =
                isRootView
                ? rootViewMethods
                : iconListMethods;

            for (NSString *methodName in methods) {

                SEL selector =
                    NSSelectorFromString(methodName);

                if ([view respondsToSelector:selector]) {

                    IARLog(@"Calling %@ on %@",
                           methodName,
                           className);

                    /*
                     * UIView methods need special handling.
                     */

                    if ([methodName isEqualToString:@"setNeedsLayout"]) {

                        [view setNeedsLayout];

                    } else if ([methodName isEqualToString:@"layoutIfNeeded"]) {

                        [view layoutIfNeeded];

                    } else if ([methodName isEqualToString:@"layoutSubviews"]) {

                        /*
                         * layoutSubviews is normally not supposed to be
                         * called directly, so don't invoke it.
                         */

                        IARLog(@"Skipping direct layoutSubviews");

                    } else {

                        IARCallVoid(view, selector);
                    }
                }
            }
        }

        for (UIView *subview in view.subviews) {
            [views addObject:subview];
        }
    }

    /*
     * Finally force UIKit layout on the visible hierarchy.
     */

    [controllerView setNeedsLayout];
    [controllerView layoutIfNeeded];

    IARLog(@"UI refresh finished");
    IARLog(@"--------------------------------");
}

#pragma mark - Add Icon

static void IARProcessBundleID(NSString *bundleID) {

    if (!bundleID.length) {
        return;
    }

    IARLog(@"================================");
    IARLog(@"PROCESSING %@", bundleID);

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

    SBHIconManager *iconManager =
        [controller iconManager];

    if (!iconManager) {
        IARLog(@"SBHIconManager unavailable");
        return;
    }

    SBIconModel *model =
        [iconManager iconModel];

    SBRootFolder *rootFolder =
        [iconManager rootFolder];

    if (!model || !rootFolder) {
        IARLog(@"model/rootFolder unavailable");
        return;
    }

    IARLog(@"Icon model = %@", model);
    IARLog(@"Root folder = %@", rootFolder);

    /*
     * Get SBIcon.
     */

    SBIcon *icon = nil;

    SEL expectedSelector =
        @selector(expectedIconForDisplayIdentifier:);

    if ([model respondsToSelector:expectedSelector]) {

        icon =
            ((id (*)(id, SEL, id))objc_msgSend)
            (model,
             expectedSelector,
             bundleID);

        IARLog(@"expectedIcon = %@", icon);
    }

    if (!icon &&
        [model respondsToSelector:
            @selector(applicationIconForBundleIdentifier:)]) {

        icon =
            ((id (*)(id, SEL, id))objc_msgSend)
            (model,
             @selector(applicationIconForBundleIdentifier:),
             bundleID);

        IARLog(@"applicationIcon = %@", icon);
    }

    if (!icon) {
        IARLog(@"FAILED: SBIcon not found");
        return;
    }

    IARLog(@"SBIcon = %@", icon);

    BOOL alreadyOnHomeScreen = NO;

    if ([rootFolder respondsToSelector:
            @selector(containsIcon:)]) {

        alreadyOnHomeScreen =
            [rootFolder containsIcon:icon];
    }

    IARLog(@"containsIcon BEFORE = %d",
           alreadyOnHomeScreen);

    if (alreadyOnHomeScreen) {

        IARLog(@"Icon already belongs to Home Screen");

        /*
         * Even if it already exists in the model, refresh UI.
         */

        dispatch_async(dispatch_get_main_queue(), ^{
            IARRefreshHomeScreen();
        });

        return;
    }

    /*
     * THIS IS THE IMPORTANT PART.
     *
     * This is the method your previous diagnostic log showed
     * successfully changing containsIcon from 0 -> 1.
     */

    SEL addSelector =
        @selector(addNewIconsToDesignatedLocations:
                              saveIconState:);

    if ([model respondsToSelector:addSelector]) {

        IARLog(@"Calling addNewIconsToDesignatedLocations");

        NSArray *icons =
            @[ icon ];

        ((void (*)(id, SEL, id, BOOL))objc_msgSend)
            (model,
             addSelector,
             icons,
             YES);

        IARLog(@"addNewIconsToDesignatedLocations finished");

    } else {

        IARLog(@"ERROR: addNewIconsToDesignatedLocations unavailable");
        return;
    }

    /*
     * Verify model state.
     */

    BOOL afterAdd = NO;

    if ([rootFolder respondsToSelector:
            @selector(containsIcon:)]) {

        afterAdd =
            [rootFolder containsIcon:icon];
    }

    IARLog(@"containsIcon AFTER = %d", afterAdd);

    if (!afterAdd) {
        IARLog(@"ERROR: icon was not inserted into root folder");
        return;
    }

    IARLog(@"SUCCESS: icon inserted into Home Screen model");

    /*
     * Give SpringBoard one run-loop cycle first.
     *
     * This is important because the icon model may send internal
     * notifications after modifying the icon state.
     */

    dispatch_async(dispatch_get_main_queue(), ^{

        IARLog(@"Refreshing Home Screen UI");

        IARRefreshHomeScreen();

        /*
         * Second refresh shortly afterwards.
         *
         * Some SpringBoard views update asynchronously.
         */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(0.25 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{

                IARLog(@"Second Home Screen UI refresh");

                IARRefreshHomeScreen();

                IARLog(@"Icon processing complete");
            }
        );
    });
}

#pragma mark - LaunchServices

static NSArray *IARGetInstalledApplications(void) {

    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {
        IARLog(@"LSApplicationWorkspace not found");
        return nil;
    }

    id workspace = nil;

    SEL defaultSelector =
        @selector(defaultWorkspace);

    if ([workspaceClass respondsToSelector:defaultSelector]) {

        workspace =
            ((id (*)(id, SEL))objc_msgSend)
            (workspaceClass,
             defaultSelector);
    }

    if (!workspace) {
        IARLog(@"defaultWorkspace unavailable");
        return nil;
    }

    SEL appsSelector =
        @selector(allInstalledApplications);

    if (![workspace respondsToSelector:appsSelector]) {
        IARLog(@"allInstalledApplications unavailable");
        return nil;
    }

    NSArray *apps =
        ((id (*)(id, SEL))objc_msgSend)
        (workspace,
         appsSelector);

    IARLog(@"LaunchServices returned %lu applications",
           (unsigned long)apps.count);

    return apps;
}

static NSArray *IARGetBundleIDs(void) {

    NSArray *apps =
        IARGetInstalledApplications();

    if (!apps) {
        return nil;
    }

    NSMutableArray *result =
        [NSMutableArray array];

    for (id app in apps) {

        NSString *bundleID = nil;

        if ([app respondsToSelector:
                @selector(bundleIdentifier)]) {

            bundleID =
                ((id (*)(id, SEL))objc_msgSend)
                (app,
                 @selector(bundleIdentifier));

        } else if ([app respondsToSelector:
                       @selector(applicationIdentifier)]) {

            bundleID =
                ((id (*)(id, SEL))objc_msgSend)
                (app,
                 @selector(applicationIdentifier));
        }

        if (bundleID.length) {
            [result addObject:bundleID];
        }
    }

    return result;
}

#pragma mark - Polling

static NSMutableSet<NSString *> *gKnownBundleIDs;

static void IARPoll(void) {

    NSArray *current =
        IARGetBundleIDs();

    if (!current) {
        IARLog(@"POLL: unable to get applications");
        return;
    }

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
            currentSet;

        return;
    }

    IARLog(@"NEW APPLICATIONS: %lu",
           (unsigned long)newApps.count);

    for (NSString *bundleID in newApps) {

        IARLog(@"NEW BUNDLE ID: %@", bundleID);

        /*
         * Always perform icon manipulation on main thread.
         */

        dispatch_async(dispatch_get_main_queue(), ^{

            IARProcessBundleID(bundleID);
        });
    }

    gKnownBundleIDs =
        currentSet;
}

#pragma mark - Constructor

%ctor {

    @autoreleasepool {

        IARLog(@"\n================================");
        IARLog(@"IconAutoRefresh loaded");
        IARLog(@"================================");

        /*
         * Everything below is intentionally kept simple.
         *
         * TrollStore Lite may not generate the Darwin notifications
         * expected from normal App Store installation, so polling
         * remains the reliable detection mechanism.
         */

        dispatch_queue_t queue =
            dispatch_get_global_queue(
                QOS_CLASS_UTILITY,
                0
            );

        dispatch_source_t timer =
            dispatch_source_create(
                DISPATCH_SOURCE_TYPE_TIMER,
                0,
                0,
                queue
            );

        if (!timer) {
            IARLog(@"ERROR: could not create timer");
            return;
        }

        IARLog(@"Creating polling timer");

        dispatch_source_set_timer(
            timer,
            dispatch_time(
                DISPATCH_TIME_NOW,
                2 * NSEC_PER_SEC
            ),
            3 * NSEC_PER_SEC,
            500 * NSEC_PER_MSEC
        );

        dispatch_source_set_event_handler(
            timer,
            ^{

                IARLog(@"Timer fired");

                /*
                 * Keep LaunchServices enumeration off SpringBoard's
                 * main thread.
                 */

                IARPoll();
            }
        );

        dispatch_resume(timer);

        IARLog(@"Polling timer started successfully");
    }
}
