#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

static id IARSharedIconController(void)
{
    Class cls = NSClassFromString(@"SBIconController");

    if (!cls)
        return nil;

    SEL selector =
        NSSelectorFromString(@"sharedInstance");

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

    SEL selector =
        NSSelectorFromString(@"model");

    if (![controller respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL))objc_msgSend)(
        controller,
        selector
    );
}

static id IARApplicationIcon(
    id model,
    NSString *bundleID
)
{
    if (!model || !bundleID.length)
        return nil;

    SEL selector =
        NSSelectorFromString(
            @"applicationIconForBundleIdentifier:"
        );

    if (![model respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL, id))objc_msgSend)(
        model,
        selector,
        bundleID
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

static id IARFindIcon(
    id model,
    NSString *bundleID
)
{
    id icon =
        IARApplicationIcon(
            model,
            bundleID
        );

    if (icon)
        return icon;

    return IARExpectedIcon(
        model,
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

static void IARProcessApplication(
    NSString *bundleID
)
{
    if (!bundleID.length)
        return;

    id controller =
        IARSharedIconController();

    if (!controller)
        return;

    id model =
        IARIconModel(controller);

    if (!model)
        return;

    id icon =
        IARFindIcon(
            model,
            bundleID
        );

    if (!icon)
        return;

    if (IARRootContainsIcon(
            controller,
            icon
        ))
        return;

    IARAddIcon(
        controller,
        icon
    );
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

    if (![application respondsToSelector:selector])
        return nil;

    return ((NSString *(*)(id, SEL))objc_msgSend)(
        application,
        selector
    );
}

static void IARProcessAddedApplications(
    id added
)
{
    if (!added)
        return;

    for (id application in added)
    {
        NSString *bundleID =
            IARBundleIdentifier(
                application
            );

        if (!bundleID.length)
            continue;

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                IARProcessApplication(
                    bundleID
                );
            }
        );
    }
}

%hook SBIconController

- (void)_mutateIconListsForInstalledAppsDidChangeWithController:(id)controller
                                                          added:(id)added
                                                       modified:(id)modified
                                                        removed:(id)removed
{
    %orig;

    IARProcessAddedApplications(
        added
    );
}

%end

%ctor
{
    @autoreleasepool
    {
        NSString *processName =
            [NSProcessInfo processInfo].processName;

        if (![processName
              isEqualToString:@"SpringBoard"])
            return;
    }
}
