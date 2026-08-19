#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSString *const kIARLogPath =
    @"/var/mobile/IconAutoRefresh.log";

static dispatch_source_t gTimer = nil;
static NSMutableSet<NSString *> *gKnownBundleIDs = nil;

#pragma mark - Logging

static void IARLog(NSString *format, ...) {

    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format
                               arguments:args];

    va_end(args);

    NSLog(@"[IconAutoRefresh] %@", message);

    NSString *line =
        [NSString stringWithFormat:
            @"[%@] %@\n",
            [NSDate date],
            message];

    NSFileManager *fm =
        [NSFileManager defaultManager];

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

#pragma mark - LaunchServices

static NSArray *IARGetInstalledApplications(void) {

    IARLog(@"IARGetInstalledApplications()");

    Class workspaceClass =
        NSClassFromString(@"LSApplicationWorkspace");

    if (!workspaceClass) {

        IARLog(
            @"ERROR: LSApplicationWorkspace class not found"
        );

        return nil;
    }

    IARLog(@"LSApplicationWorkspace class found");

    SEL defaultWorkspace =
        NSSelectorFromString(@"defaultWorkspace");

    if (![workspaceClass respondsToSelector:
                            defaultWorkspace]) {

        IARLog(
            @"ERROR: defaultWorkspace unavailable"
        );

        return nil;
    }

    id workspace =
        ((id (*)(id, SEL))objc_msgSend)
        (workspaceClass,
         defaultWorkspace);

    if (!workspace) {

        IARLog(
            @"ERROR: defaultWorkspace returned nil"
        );

        return nil;
    }

    IARLog(@"defaultWorkspace OK");

    SEL allInstalled =
        NSSelectorFromString(
            @"allInstalledApplications"
        );

    if (![workspace respondsToSelector:
                         allInstalled]) {

        IARLog(
            @"ERROR: allInstalledApplications unavailable"
        );

        return nil;
    }

    NSArray *apps =
        ((id (*)(id, SEL))objc_msgSend)
        (workspace,
         allInstalled);

    if (!apps) {

        IARLog(
            @"ERROR: allInstalledApplications returned nil"
        );

        return nil;
    }

    IARLog(
        @"LaunchServices returned %lu applications",
        (unsigned long)apps.count
    );

    return apps;
}

static NSString *IARGetBundleID(id application) {

    if (!application)
        return nil;

    SEL selector =
        NSSelectorFromString(@"bundleIdentifier");

    if ([application respondsToSelector:selector]) {

        return ((id (*)(id, SEL))objc_msgSend)
            (application,
             selector);
    }

    selector =
        NSSelectorFromString(
            @"applicationIdentifier"
        );

    if ([application respondsToSelector:selector]) {

        return ((id (*)(id, SEL))objc_msgSend)
            (application,
             selector);
    }

    return nil;
}

static NSSet<NSString *> *IARGetBundleIDs(void) {

    NSArray *applications =
        IARGetInstalledApplications();

    if (!applications)
        return nil;

    NSMutableSet *result =
        [NSMutableSet set];

    for (id application in applications) {

        NSString *bundleID =
            IARGetBundleID(application);

        if (bundleID.length > 0) {

            [result addObject:bundleID];
        }
    }

    return result;
}

#pragma mark - Poll

static void IARPoll(void) {

    IARLog(
        @"========== POLL =========="
    );

    IARLog(
        @"Main thread: %d",
        [NSThread isMainThread]
    );

    NSSet<NSString *> *current =
        IARGetBundleIDs();

    if (!current) {

        IARLog(
            @"POLL FAILED: no bundle IDs"
        );

        return;
    }

    if (!gKnownBundleIDs) {

        gKnownBundleIDs =
            [current mutableCopy];

        IARLog(
            @"BASELINE: %lu applications",
            (unsigned long)current.count
        );

        return;
    }

    NSMutableSet *newApps =
        [current mutableCopy];

    [newApps minusSet:gKnownBundleIDs];

    if (newApps.count == 0) {

        IARLog(
            @"No new applications"
        );

    } else {

        IARLog(
            @"NEW APPLICATIONS: %lu",
            (unsigned long)newApps.count
        );

        for (NSString *bundleID in newApps) {

            IARLog(
                @"NEW BUNDLE ID: %@",
                bundleID
            );
        }
    }

    gKnownBundleIDs =
        [current mutableCopy];
}

#pragma mark - Timer

static void IARStartTimer(void) {

    if (gTimer) {

        IARLog(
            @"Timer already exists"
        );

        return;
    }

    IARLog(
        @"Creating polling timer"
    );

    gTimer =
        dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER,
            0,
            0,
            dispatch_get_main_queue()
        );

    if (!gTimer) {

        IARLog(
            @"ERROR: timer creation failed"
        );

        return;
    }

    dispatch_source_set_timer(
        gTimer,
        dispatch_time(
            DISPATCH_TIME_NOW,
            1 * NSEC_PER_SEC
        ),
        3 * NSEC_PER_SEC,
        500 * NSEC_PER_MSEC
    );

    dispatch_source_set_event_handler(
        gTimer,
        ^{

            IARLog(
                @"Timer fired"
            );

            IARPoll();
        }
    );

    dispatch_resume(gTimer);

    IARLog(
        @"Polling timer started successfully"
    );
}

#pragma mark - Constructor

%ctor {

    @autoreleasepool {

        IARLog(
            @"================================"
        );

        IARLog(
            @"IconAutoRefresh loaded"
        );

        IARLog(
            @"Starting application monitor"
        );

        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                IARStartTimer();

            }
        );

        IARLog(
            @"Initialization complete"
        );
    }
}
