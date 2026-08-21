#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSUInteger IARPreviousApplicationCount = 0;
static dispatch_source_t IARTimer = nil;
static BOOL IARRefreshInProgress = NO;
static BOOL IARRetryScheduled = NO;

static NSUInteger IARGetApplicationCount(void)
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

    if (![applications isKindOfClass:[NSArray class]])
        return 0;

    return applications.count;
}

static id IARGetIconController(void)
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

static id IARGetIconModel(void)
{
    id controller =
        IARGetIconController();

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

static BOOL IARCallVoidSelector(
    id object,
    SEL selector
)
{
    if (!object)
        return NO;

    if (![object respondsToSelector:selector])
        return NO;

    ((void (*)(id, SEL))objc_msgSend)(
        object,
        selector
    );

    return YES;
}

static BOOL IARRefreshIconModel(void)
{
    id model =
        IARGetIconModel();

    if (!model)
        return NO;

    BOOL changed = NO;

    SEL reloadSEL =
        sel_registerName("reload");

    if (IARCallVoidSelector(model, reloadSEL))
        changed = YES;

    SEL reloadIconsSEL =
        sel_registerName("reloadIcons");

    if (IARCallVoidSelector(model, reloadIconsSEL))
        changed = YES;

    SEL updateIconStateSEL =
        sel_registerName("updateIconState");

    if (IARCallVoidSelector(model, updateIconStateSEL))
        changed = YES;

    SEL saveIconStateSEL =
        sel_registerName("saveIconState");

    if (IARCallVoidSelector(model, saveIconStateSEL))
        changed = YES;

    return changed;
}

static void IARPerformRefresh(void)
{
    if (IARRefreshInProgress)
        return;

    IARRefreshInProgress = YES;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            IARRefreshIconModel();

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
                    IARRefreshInProgress = NO;
                }
            );
        }
    );
}

static void IARScheduleRefresh(void)
{
    if (IARRetryScheduled)
        return;

    IARRetryScheduled = YES;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                1.5 *
                NSEC_PER_SEC
            )
        ),
        dispatch_get_main_queue(),
        ^{
            IARRetryScheduled = NO;

            IARPerformRefresh();
        }
    );
}

static void IARCheckForApplicationChanges(void)
{
    NSUInteger currentCount =
        IARGetApplicationCount();

    if (currentCount == 0)
        return;

    if (IARPreviousApplicationCount == 0) {
        IARPreviousApplicationCount =
            currentCount;

        return;
    }

    if (currentCount ==
        IARPreviousApplicationCount) {
        return;
    }

    IARPreviousApplicationCount =
        currentCount;

    IARScheduleRefresh();
}

static void IARStartWatcher(void)
{
    if (IARTimer)
        return;

    IARPreviousApplicationCount =
        IARGetApplicationCount();

    if (IARPreviousApplicationCount == 0)
        IARPreviousApplicationCount = 0;

    IARTimer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_global_queue(
                QOS_CLASS_UTILITY,
                0
            )
        );

    if (!IARTimer)
        return;

    dispatch_source_set_timer(
        IARTimer,
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                5.0 *
                NSEC_PER_SEC
            )
        ),
        (uint64_t)(
            5.0 *
            NSEC_PER_SEC
        ),
        (uint64_t)(
            1.0 *
            NSEC_PER_SEC
        )
    );

    dispatch_source_set_event_handler(
        IARTimer,
        ^{
            IARCheckForApplicationChanges();
        }
    );

    dispatch_resume(IARTimer);
}

%hook SBIconController

- (void)applicationDidFinishLaunching:(id)application
{
    %orig;

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
            IARStartWatcher();
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
                IARStartWatcher();
            }
        );
    }
}
