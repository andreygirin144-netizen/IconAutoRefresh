#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSUInteger gPreviousApplicationCount = 0;
static dispatch_source_t gTimer = nil;

static NSUInteger IARApplicationCount(void)
{
    Class workspaceClass = objc_getClass("LSApplicationWorkspace");

    if (!workspaceClass)
        return 0;

    SEL defaultWorkspaceSEL =
        sel_registerName("defaultWorkspace");

    if (![workspaceClass respondsToSelector:defaultWorkspaceSEL])
        return 0;

    id workspace =
        ((id (*)(id, SEL))objc_msgSend)(
            workspaceClass,
            defaultWorkspaceSEL
        );

    if (!workspace)
        return 0;

    SEL allApplicationsSEL =
        sel_registerName("allApplications");

    if (![workspace respondsToSelector:allApplicationsSEL])
        return 0;

    NSArray *applications =
        ((id (*)(id, SEL))objc_msgSend)(
            workspace,
            allApplicationsSEL
        );

    return applications.count;
}

static id IARIconController(void)
{
    Class controllerClass =
        objc_getClass("SBIconController");

    if (!controllerClass)
        return nil;

    SEL sharedInstanceSEL =
        sel_registerName("sharedInstance");

    if (![controllerClass respondsToSelector:sharedInstanceSEL])
        return nil;

    return
        ((id (*)(id, SEL))objc_msgSend)(
            controllerClass,
            sharedInstanceSEL
        );
}

static id IARIconModel(void)
{
    id controller = IARIconController();

    if (!controller)
        return nil;

    SEL modelSEL =
        sel_registerName("model");

    if (![controller respondsToSelector:modelSEL])
        return nil;

    return
        ((id (*)(id, SEL))objc_msgSend)(
            controller,
            modelSEL
        );
}

static void IARInvokeIfAvailable(
    id object,
    const char *selectorName
)
{
    if (!object)
        return;

    SEL selector =
        sel_registerName(selectorName);

    if (![object respondsToSelector:selector])
        return;

    ((void (*)(id, SEL))objc_msgSend)(
        object,
        selector
    );
}

static void IARRefresh(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            id model = IARIconModel();

            if (!model)
                return;

            IARInvokeIfAvailable(
                model,
                "reload"
            );

            IARInvokeIfAvailable(
                model,
                "reloadIcons"
            );

            IARInvokeIfAvailable(
                model,
                "updateIconState"
            );

            IARInvokeIfAvailable(
                model,
                "saveIconState"
            );
        }
    );
}

static void IARCheckApplications(void)
{
    NSUInteger currentCount =
        IARApplicationCount();

    if (currentCount == 0)
        return;

    if (gPreviousApplicationCount == 0) {
        gPreviousApplicationCount =
            currentCount;

        return;
    }

    if (currentCount !=
        gPreviousApplicationCount) {

        gPreviousApplicationCount =
            currentCount;

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(
                    1.0 *
                    NSEC_PER_SEC
                )
            ),
            dispatch_get_main_queue(),
            ^{
                IARRefresh();
            }
        );

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(
                    3.0 *
                    NSEC_PER_SEC
                )
            ),
            dispatch_get_main_queue(),
            ^{
                IARRefresh();
            }
        );

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(
                    6.0 *
                    NSEC_PER_SEC
                )
            ),
            dispatch_get_main_queue(),
            ^{
                IARRefresh();
            }
        );
    }
}

static void IARStartTimer(void)
{
    if (gTimer)
        return;

    gPreviousApplicationCount =
        IARApplicationCount();

    gTimer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_main_queue()
        );

    if (!gTimer)
        return;

    dispatch_source_set_timer(
        gTimer,
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                3.0 *
                NSEC_PER_SEC
            )
        ),
        (uint64_t)(
            3.0 *
            NSEC_PER_SEC
        ),
        (uint64_t)(
            0.5 *
            NSEC_PER_SEC
        )
    );

    dispatch_source_set_event_handler(
        gTimer,
        ^{
            IARCheckApplications();
        }
    );

    dispatch_resume(gTimer);
}

%hook SBIconController

- (void)applicationDidFinishLaunching:(id)application
{
    %orig;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                2.0 *
                NSEC_PER_SEC
            )
        ),
        dispatch_get_main_queue(),
        ^{
            IARStartTimer();
        }
    );
}

%end

%ctor
{
    @autoreleasepool {

        NSString *bundleIdentifier =
            [NSBundle.mainBundle bundleIdentifier];

        if (![bundleIdentifier
              isEqualToString:@"com.apple.springboard"])
            return;

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(
                    5.0 *
                    NSEC_PER_SEC
                )
            ),
            dispatch_get_main_queue(),
            ^{
                IARStartTimer();
            }
        );
    }
}
