#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBFolder : NSObject
- (BOOL)containsIcon:(id)icon;
@end

@interface SBRootFolder : SBFolder
@end

@interface SBHIconModel : NSObject
- (SBIcon *)expectedIconForDisplayIdentifier:(NSString *)bundleID;
- (SBIcon *)applicationIconForBundleIdentifier:(NSString *)bundleID;
- (SBIcon *)addApplicationIconForBundleIdentifier:(NSString *)bundleID;
- (void)saveIconState;
@end

@interface SBHIconManager : NSObject
- (SBHIconModel *)iconModel;
- (SBRootFolder *)rootFolder;
- (void)addNewIconToFirstAvailablePage:(id)icon animate:(BOOL)animate;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
- (void)addNewIconToFirstAvailablePage:(id)icon animate:(BOOL)animate;
@end

@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
@end

static void ProcessInstalledApplications(id applications) {
    SBIconController *controller = [NSClassFromString(@"SBIconController") sharedInstance];
    if (!controller) return;

    SBHIconManager *iconManager = nil;
    if ([controller respondsToSelector:@selector(iconManager)]) {
        iconManager = [controller iconManager];
    }
    if (!iconManager) return;

    SBHIconModel *model = nil;
    if ([iconManager respondsToSelector:@selector(iconModel)]) {
        model = [iconManager iconModel];
    }

    SBRootFolder *rootFolder = nil;
    if ([iconManager respondsToSelector:@selector(rootFolder)]) {
        rootFolder = [iconManager rootFolder];
    }

    if (!model || !rootFolder) return;

    NSArray *appsArray = [applications respondsToSelector:@selector(allObjects)] 
                        ? [applications allObjects] 
                        : (NSArray *)applications;
    
    BOOL iconAdded = NO;

    for (id appObj in appsArray) {
        NSString *bundleID = nil;
        if ([appObj isKindOfClass:[NSString class]]) {
            bundleID = (NSString *)appObj;
        } else if ([appObj respondsToSelector:@selector(bundleIdentifier)]) {
            bundleID = [appObj bundleIdentifier];
        }

        if (!bundleID) continue;

        SBIcon *icon = nil;
        if ([model respondsToSelector:@selector(expectedIconForDisplayIdentifier:)]) {
            icon = [model expectedIconForDisplayIdentifier:bundleID];
        }
        if (!icon && [model respondsToSelector:@selector(applicationIconForBundleIdentifier:)]) {
            icon = [model applicationIconForBundleIdentifier:bundleID];
        }
        if (!icon && [model respondsToSelector:@selector(addApplicationIconForBundleIdentifier:)]) {
            icon = [model addApplicationIconForBundleIdentifier:bundleID];
        }

        if (!icon) continue;

        BOOL isOnHomeScreen = NO;
        if ([rootFolder respondsToSelector:@selector(containsIcon:)]) {
            isOnHomeScreen = [rootFolder containsIcon:icon];
        }

        if (!isOnHomeScreen) {
            if ([controller respondsToSelector:@selector(addNewIconToFirstAvailablePage:animate:)]) {
                [controller addNewIconToFirstAvailablePage:icon animate:NO];
                iconAdded = YES;
            } else if ([iconManager respondsToSelector:@selector(addNewIconToFirstAvailablePage:animate:)]) {
                [iconManager addNewIconToFirstAvailablePage:icon animate:NO];
                iconAdded = YES;
            }
        }
    }

    if (iconAdded && [model respondsToSelector:@selector(saveIconState)]) {
        [model saveIconState];
    }
}

%hook SBHIconManager

- (void)applicationsDidInstall:(id)applications {
    %orig;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ProcessInstalledApplications(applications);
    });
}

%end

%ctor {
    %init(_ungrouped);
}
