#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id gWorkspaceObserver = nil;
static BOOL gObserverStarted = NO;
static BOOL gRefreshScheduled = NO;

static NSString *IARBundleIdentifierFromApplication(id application);

static id IARSendObject(id object, SEL selector)
{
    if (!object || ![object respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL))objc_msgSend)(
        object,
        selector
    );
}

static id IARSendObjectWithObject(
    id object,
    SEL selector,
    id argument
)
{
    if (!object || ![object respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL, id))objc_msgSend)(
        object,
        selector,
        argument
    );
}

static void IARSendVoid(id object, SEL selector)
{
    if (!object || ![object respondsToSelector:selector])
        return;

    ((void (*)(id, SEL))objc_msgSend)(
        object,
        selector
    );
}

static id IARIconController(void)
{
    Class cls = objc_getClass("SBIconController");

    if (!cls)
        return nil;

    SEL selector = sel_registerName("sharedInstance");

    if (![cls respondsToSelector:selector])
        return nil;

    return IARSendObject(
        cls,
        selector
    );
}

static id IARIconModel(void)
{
    id controller = IARIconController();

    if (!controller)
        return nil;

    SEL selector = sel_registerName("model");

    return IARSendObject(
        controller,
        selector
    );
}

static BOOL IARIconExistsForBundleIdentifier(
    NSString *bundleIdentifier
)
{
    if (!bundleIdentifier.length)
        return NO;

    id model = IARIconModel();

    if (!model)
        return NO;

    SEL selector =
        sel_registerName(
            "applicationIconForBundleIdentifier:"
        );

    id icon = IARSendObjectWithObject(
        model,
        selector,
        bundleIdentifier
    );

    return icon != nil;
}

static void IARReloadIcons(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            id model = IARIconModel();

            if (!model)
                return;

            SEL selector =
                sel_registerName("reloadIcons");

            if ([model respondsToSelector:selector])
            {
                IARSendVoid(
                    model,
                    selector
                );
            }
        }
    );
}

static void IARRefreshForBundleIdentifier(
    NSString *bundleIdentifier
)
{
    if (!bundleIdentifier.length)
        return;

    if (IARIconExistsForBundleIdentifier(
            bundleIdentifier))
    {
        return;
    }

    IARReloadIcons();
}

static void IARScheduleRefresh(
    NSString *bundleIdentifier
)
{
    if (!bundleIdentifier.length)
        return;

    if (gRefreshScheduled)
        return;

    gRefreshScheduled = YES;

    NSString *identifier =
        [bundleIdentifier copy];

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.6 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            IARRefreshForBundleIdentifier(
                identifier
            );

            gRefreshScheduled = NO;
        }
    );
}

@interface IARWorkspaceObserver : NSObject
@end

@implementation IARWorkspaceObserver

- (void)applicationInstalled:(id)application
{
    NSString *bundleIdentifier =
        IARBundleIdentifierFromApplication(
            application
        );

    if (bundleIdentifier.length)
    {
        IARScheduleRefresh(
            bundleIdentifier
        );
    }
}

- (void)applicationsDidInstall:(NSArray *)applications
{
    for (id application in applications)
    {
        NSString *bundleIdentifier =
            IARBundleIdentifierFromApplication(
                application
            );

        if (bundleIdentifier.length)
        {
            IARScheduleRefresh(
                bundleIdentifier
            );
        }
    }
}

- (void)applicationWasInstalled:(id)application
{
    NSString *bundleIdentifier =
        IARBundleIdentifierFromApplication(
            application
        );

    if (bundleIdentifier.length)
    {
        IARScheduleRefresh(
            bundleIdentifier
        );
    }
}

@end

static NSString *IARBundleIdentifierFromApplication(
    id application
)
{
    if (!application)
        return nil;

    SEL selector =
        sel_registerName("bundleIdentifier");

    id value =
        IARSendObject(
            application,
            selector
        );

    if ([value isKindOfClass:[NSString class]])
        return value;

    return nil;
}

static void IARStartObserver(void)
{
    if (gObserverStarted)
        return;

    Class workspaceClass =
        objc_getClass("LSApplicationWorkspace");

    if (!workspaceClass)
        return;

    SEL defaultWorkspaceSEL =
        sel_registerName("defaultWorkspace");

    if (![workspaceClass respondsToSelector:
          defaultWorkspaceSEL])
    {
        return;
    }

    id workspace =
        IARSendObject(
            workspaceClass,
            defaultWorkspaceSEL
        );

    if (!workspace)
        return;

    SEL addObserverSEL =
        sel_registerName("addObserver:");

    if (![workspace respondsToSelector:
          addObserverSEL])
    {
        return;
    }

    IARWorkspaceObserver *observer =
        [IARWorkspaceObserver new];

    gWorkspaceObserver = observer;

    ((void (*)(id, SEL, id))objc_msgSend)(
        workspace,
        addObserverSEL,
        observer
    );

    gObserverStarted = YES;
}

%hook SBIconController

- (void)applicationDidFinishLaunching:(id)application
{
    %orig;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(2.0 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            IARStartObserver();
        }
    );
}

%end

%ctor
{
    @autoreleasepool
    {
        NSString *bundleIdentifier =
            [[NSBundle mainBundle]
                bundleIdentifier];

        if (![bundleIdentifier
              isEqualToString:
              @"com.apple.springboard"])
        {
            return;
        }

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(4.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                IARStartObserver();
            }
        );
    }
}
