#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

static NSString *IARLogPath(void)
{
    return @"/var/mobile/IconAutoRefresh-Debug.log";
}

static void IARLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:IARLogPath()];
    if (!file) {
        [[NSFileManager defaultManager] createFileAtPath:IARLogPath() contents:nil attributes:nil];
        file = [NSFileHandle fileHandleForWritingAtPath:IARLogPath()];
    }
    if (!file) return;
    [file seekToEndOfFile];
    [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

static id IARSharedIconController(void)
{
    Class cls = NSClassFromString(@"SBIconController");
    if (!cls) return nil;
    SEL selector = NSSelectorFromString(@"sharedInstance");
    if (![cls respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)((id)cls, selector);
}

static id IARIconModel(id controller)
{
    if (!controller) return nil;
    SEL selector = NSSelectorFromString(@"model");
    if (![controller respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(controller, selector);
}

static id IARRootFolder(id controller)
{
    if (!controller) return nil;
    SEL selector = NSSelectorFromString(@"rootFolder");
    if (![controller respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(controller, selector);
}

static id IARApplicationIcon(id model, NSString *bundleID)
{
    if (!model || !bundleID.length) return nil;
    SEL selector = NSSelectorFromString(@"applicationIconForBundleIdentifier:");
    if (![model respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(model, selector, bundleID);
}

static id IARExpectedIcon(id model, NSString *bundleID)
{
    if (!model || !bundleID.length) return nil;
    SEL selector = NSSelectorFromString(@"expectedIconForDisplayIdentifier:");
    if (![model respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(model, selector, bundleID);
}

static id IARFindIcon(id model, NSString *bundleID)
{
    id icon = IARApplicationIcon(model, bundleID);
    if (icon) {
        IARLog(@"Found via applicationIconForBundleIdentifier: %@", bundleID);
        return icon;
    }
    icon = IARExpectedIcon(model, bundleID);
    if (icon) {
        IARLog(@"Found via expectedIconForDisplayIdentifier: %@", bundleID);
    }
    return icon;
}

static BOOL IARRootContainsIcon(id rootFolder, id icon)
{
    if (!rootFolder || !icon) return NO;
    SEL selector = NSSelectorFromString(@"containsIcon:");
    if (![rootFolder respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(rootFolder, selector, icon);
}

static BOOL IARAddIcon(id controller, id icon)
{
    if (!controller || !icon) return NO;
    SEL selector = NSSelectorFromString(@"addIconToHomeScreen:");
    if (![controller respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, icon);
    return YES;
}

static void IARForceLayout(id controller)
{
    if (!controller) return;
    SEL layoutSelector = NSSelectorFromString(@"layoutIconListsWithAnimationType:forceRelayout:");
    id iconManager = [controller valueForKey:@"iconManager"];
    if (iconManager && [iconManager respondsToSelector:layoutSelector]) {
        ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(iconManager, layoutSelector, 0, YES);
        IARLog(@"Force layout executed");
    } else {
        IARLog(@"Force layout FAILED - iconManager: %@", iconManager);
    }
}

static NSString *IARBundleIdentifierFromApplication(id application)
{
    if (!application) return nil;
    
    if ([application isKindOfClass:[NSString class]]) {
        return (NSString *)application;
    }
    
    SEL selector1 = NSSelectorFromString(@"applicationIdentifier");
    if ([application respondsToSelector:selector1]) {
        return ((NSString *(*)(id, SEL))objc_msgSend)(application, selector1);
    }
    SEL selector2 = NSSelectorFromString(@"bundleIdentifier");
    if ([application respondsToSelector:selector2]) {
        return ((NSString *(*)(id, SEL))objc_msgSend)(application, selector2);
    }
    return nil;
}

static void IARProcessApplication(NSString *bundleID, int retryCount)
{
    IARLog(@"Processing application: %@ (retry: %d)", bundleID, retryCount);
    
    if (!bundleID.length) {
        IARLog(@"ERROR: Empty bundle ID");
        return;
    }
    
    id controller = IARSharedIconController();
    if (!controller) {
        IARLog(@"ERROR: Cannot get SBIconController");
        return;
    }
    IARLog(@"Got SBIconController: %@", controller);
    
    id model = IARIconModel(controller);
    if (!model) {
        IARLog(@"ERROR: Cannot get icon model");
        return;
    }
    IARLog(@"Got icon model: %@", model);
    
    id rootFolder = IARRootFolder(controller);
    if (!rootFolder) {
        IARLog(@"ERROR: Cannot get root folder");
        return;
    }
    IARLog(@"Got root folder: %@", rootFolder);
    
    id icon = IARFindIcon(model, bundleID);
    if (!icon) {
        IARLog(@"ERROR: Cannot find icon for %@", bundleID);
        if (retryCount < 3) {
            IARLog(@"Retry %d for %@", retryCount + 1, bundleID);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                IARProcessApplication(bundleID, retryCount + 1);
            });
        }
        return;
    }
    IARLog(@"Found icon: %@", icon);
    
    if (IARRootContainsIcon(rootFolder, icon)) {
        IARLog(@"Icon %@ already exists on Home Screen", bundleID);
        return;
    }
    IARLog(@"Icon %@ not found on Home Screen, adding...", bundleID);
    
    if (IARAddIcon(controller, icon)) {
        IARLog(@"Icon %@ added successfully", bundleID);
        IARForceLayout(controller);
    } else {
        IARLog(@"ERROR: Failed to add icon %@", bundleID);
    }
}

static void IARProcessAddedApplications(id added)
{
    if (!added) {
        IARLog(@"No added applications");
        return;
    }
    
    IARLog(@"Processing added applications: %@", added);
    
    for (id application in added) {
        NSString *bundleID = IARBundleIdentifierFromApplication(application);
        if (!bundleID.length) {
            IARLog(@"WARNING: Cannot get bundle ID for application: %@", application);
            continue;
        }
        IARLog(@"Found added app: %@", bundleID);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            IARProcessApplication(bundleID, 0);
        });
    }
}

%hook SBIconController

- (void)_mutateIconListsForInstalledAppsDidChangeWithController:(id)controller
                                                          added:(id)added
                                                       modified:(id)modified
                                                        removed:(id)removed
{
    IARLog(@"========================================");
    IARLog(@"_mutateIconListsForInstalledAppsDidChangeWithController CALLED");
    IARLog(@"Added: %@", added);
    IARLog(@"Modified: %@", modified);
    IARLog(@"Removed: %@", removed);
    IARLog(@"========================================");
    
    %orig;
    
    if (added && [added count] > 0) {
        IARProcessAddedApplications(added);
    }
}

- (void)iconManagerDidFinishInstallForIcon:(id)icon
{
    IARLog(@"========================================");
    IARLog(@"iconManagerDidFinishInstallForIcon CALLED");
    IARLog(@"Icon: %@", icon);
    IARLog(@"========================================");
    
    %orig;
    
    NSString *bundleID = nil;
    SEL bundleSelector = NSSelectorFromString(@"applicationBundleIdentifier");
    if ([icon respondsToSelector:bundleSelector]) {
        bundleID = ((NSString *(*)(id, SEL))objc_msgSend)(icon, bundleSelector);
    }
    if (bundleID.length) {
        IARLog(@"Icon bundle ID: %@", bundleID);
        IARProcessApplication(bundleID, 0);
    }
}

%end

%hook SBHIconManager

- (void)addNewIconsToDesignatedLocations:(id)locations saveIconState:(BOOL)saveState
{
    IARLog(@"========================================");
    IARLog(@"addNewIconsToDesignatedLocations CALLED");
    IARLog(@"Locations: %@", locations);
    IARLog(@"SaveIconState: %d", saveState);
    IARLog(@"========================================");
    
    %orig;
}

%end

%ctor
{
    @autoreleasepool
    {
        NSString *processName = [NSProcessInfo processInfo].processName;
        if (![processName isEqualToString:@"SpringBoard"]) return;
        
        IARLog(@"========================================");
        IARLog(@"IconAutoRefresh FINAL HOOK ACTIVATED");
        IARLog(@"iOS: %@", UIDevice.currentDevice.systemVersion);
        IARLog(@"========================================");
    }
}
