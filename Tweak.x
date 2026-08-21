#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

static NSMutableSet *IARKnownApplications;
static dispatch_source_t IARTimer;

static id IARSharedIconController(void)
{
    Class cls = NSClassFromString(@"SBIconController");

    if (!cls)
        return nil;

    SEL selector = NSSelectorFromString(@"sharedInstance");

    if (![cls respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL))objc_msgSend)(
        (id)cls,
        selector
    );
}

static id IARIconModel(id controller)
{
    if (!controller)
        return nil;

    SEL selector = NSSelectorFromString(@"model");

    if (![controller respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL))objc_msgSend)(
        controller,
        selector
    );
}

static id IARExpectedIcon(
    id model,
    NSString *bundleID
)
{
    if (!model || !bundleID.length)
        return nil;

    SEL selector =
        NSSelectorFromString(
            @"expectedIconForDisplayIdentifier:"
        );

    if (![model respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL, id))objc_msgSend)(
        model,
        selector,
        bundleID
    );
}

static BOOL IARRootContainsIcon(
    id controller,
    id icon
)
{
    if (!controller || !icon)
        return NO;

    SEL rootFolderSelector =
        NSSelectorFromString(@"rootFolder");

    if (![controller respondsToSelector:
          rootFolderSelector])
        return NO;

    id rootFolder =
        ((id (*)(id, SEL))objc_msgSend)(
            controller,
            rootFolderSelector
        );

    if (!rootFolder)
        return NO;

    SEL containsSelector =
        NSSelectorFromString(@"containsIcon:");

    if (![rootFolder respondsToSelector:
          containsSelector])
        return NO;

    return ((BOOL (*)(id, SEL, id))objc_msgSend)(
        rootFolder,
        containsSelector,
        icon
    );
}

static BOOL IARAddIcon(
    id controller,
    id icon
)
{
    if (!controller || !icon)
        return NO;

    SEL selector =
        NSSelectorFromString(
            @"addIconToHomeScreen:"
        );

    if (![controller respondsToSelector:selector])
        return NO;

    ((void (*)(id, SEL, id))objc_msgSend)(
        controller,
        selector,
        icon
    );

    return YES;
}

static BOOL IARProcessApplication(
    NSString *bundleID
)
{
    if (!bundleID.length)
        return NO;

    id controller =
        IARSharedIconController();

    if (!controller)
        return NO;

    id model =
        IARIconModel(controller);

    if (!model)
        return NO;

    id icon =
        IARExpectedIcon(
            model,
            bundleID
        );

    if (!icon)
        return NO;

    if (IARRootContainsIcon(
            controller,
            icon
        ))
    {
        return YES;
    }

    return IARAddIcon(
        controller,
        icon
    );
}

static void IARRetryApplication(
    NSString *bundleID,
    NSUInteger attempt
)
{
    if (!bundleID.length)
        return;

    if (IARProcessApplication(bundleID))
        return;

    if (attempt >= 6)
        return;

    static const double delays[] = {
        0.5,
        1.0,
        1.5,
        2.0,
        3.0,
        4.0
    };

    double delay = delays[attempt];

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(delay * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            IARRetryApplication(
                bundleID,
                attempt + 1
            );
        }
    );
}

static NSArray *IARInstalledApplications(void)
{
    Class workspaceClass =
        NSClassFromString(
            @"LSApplicationWorkspace"
        );

    if (!workspaceClass)
        return @[];

    SEL defaultSelector =
        NSSelectorFromString(
            @"defaultWorkspace"
        );

    if (![workspaceClass respondsToSelector:
          defaultSelector])
        return @[];

    id workspace =
        ((id (*)(id, SEL))objc_msgSend)(
            (id)workspaceClass,
            defaultSelector
        );

    if (!workspace)
        return @[];

    SEL allAppsSelector =
        NSSelectorFromString(
            @"allApplications"
        );

    if (![workspace respondsToSelector:
          allAppsSelector])
        return @[];

    NSArray *apps =
        ((NSArray *(*)(id, SEL))objc_msgSend)(
            workspace,
            allAppsSelector
        );

    return apps ?: @[];
}

static NSString *IARBundleIdentifier(
    id application
)
{
    if (!application)
        return nil;

    SEL selector =
        NSSelectorFromString(
            @"applicationIdentifier"
        );

    if (![application respondsToSelector:
          selector])
        return nil;

    return ((NSString *(*)(id, SEL))objc_msgSend)(
        application,
        selector
    );
}

static void IARPoll(void)
{
    NSArray *applications =
        IARInstalledApplications();

    NSMutableSet *current =
        [NSMutableSet
            setWithCapacity:applications.count];

    for (id application in applications)
    {
        NSString *bundleID =
            IARBundleIdentifier(
                application
            );

        if (bundleID.length)
            [current addObject:bundleID];
    }

    if (!IARKnownApplications)
    {
        IARKnownApplications =
            [current mutableCopy];

        return;
    }

    NSMutableSet *newApplications =
        [current mutableCopy];

    [newApplications
        minusSet:IARKnownApplications];

    for (NSString *bundleID in newApplications)
    {
        NSString *identifier =
            [bundleID copy];

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(1.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                IARRetryApplication(
                    identifier,
                    0
                );
            }
        );
    }

    IARKnownApplications =
        [current mutableCopy];
}

static void IARStart(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            IARPoll();

            if (IARTimer)
                return;

            IARTimer =
                dispatch_source_create(
                    DISPATCH_SOURCE_TYPE_TIMER,
                    0,
                    0,
                    dispatch_get_main_queue()
                );

            if (!IARTimer)
                return;

            dispatch_source_set_timer(
                IARTimer,
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(3.0 * NSEC_PER_SEC)
                ),
                (uint64_t)(3.0 * NSEC_PER_SEC),
                (uint64_t)(0.5 * NSEC_PER_SEC)
            );

            dispatch_source_set_event_handler(
                IARTimer,
                ^{
                    IARPoll();
                }
            );

            dispatch_resume(IARTimer);
        }
    );
}

%ctor
{
    NSString *processName =
        [NSProcessInfo processInfo].processName;

    if ([processName isEqualToString:@"SpringBoard"])
        IARStart();
}
