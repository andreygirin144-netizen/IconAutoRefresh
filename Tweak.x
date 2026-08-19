#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Logging

static NSString *const kLogPath = @"/var/mobile/IconAutoRefresh.log";

static void IARLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);

    NSLog(@"[IconAutoRefresh] %@", message);

    NSString *line = [NSString stringWithFormat:
        @"[%@] %@\n",
        [NSDate date],
        message
    ];

    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:kLogPath]) {
        [fm createFileAtPath:kLogPath
                    contents:nil
                  attributes:nil];
    }

    NSFileHandle *handle =
        [NSFileHandle fileHandleForWritingAtPath:kLogPath];

    if (handle) {
        [handle seekToEndOfFile];

        [handle writeData:
            [line dataUsingEncoding:NSUTF8StringEncoding]];

        [handle closeFile];
    }
}

#pragma mark - Runtime method scanner

static BOOL IARMethodNameIsInteresting(NSString *name) {

    NSArray *keywords = @[
        @"add",
        @"insert",
        @"remove",
        @"delete",
        @"move",
        @"icon",
        @"folder",
        @"state",
        @"save",
        @"model",
        @"application",
        @"display",
        @"home",
        @"root",
        @"page",
        @"layout",
        @"update",
        @"reload",
        @"refresh"
    ];

    NSString *lower =
        [name lowercaseString];

    for (NSString *keyword in keywords) {
        if ([lower containsString:keyword]) {
            return YES;
        }
    }

    return NO;
}

static void IARDumpMethodsForClass(Class cls) {

    if (!cls) {
        return;
    }

    NSString *className =
        NSStringFromClass(cls);

    IARLog(@"");
    IARLog(@"================================");
    IARLog(@"METHOD DUMP: %@", className);
    IARLog(@"================================");

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(cls, &count);

    if (!methods) {
        IARLog(@"No methods returned");
        return;
    }

    NSMutableArray *names =
        [NSMutableArray array];

    for (unsigned int i = 0; i < count; i++) {

        SEL selector =
            method_getName(methods[i]);

        if (!selector) {
            continue;
        }

        NSString *name =
            NSStringFromSelector(selector);

        if (IARMethodNameIsInteresting(name)) {
            [names addObject:name];
        }
    }

    free(methods);

    [names sortUsingSelector:@selector(compare:)];

    IARLog(@"Total interesting methods: %lu",
           (unsigned long)names.count);

    for (NSString *name in names) {
        IARLog(@"  %@", name);
    }
}

#pragma mark - Class hierarchy

static void IARDumpHierarchy(Class cls) {

    if (!cls) {
        return;
    }

    IARLog(@"");
    IARLog(@"CLASS HIERARCHY");

    Class current = cls;

    while (current) {

        IARLog(@"  %@", NSStringFromClass(current));

        current = class_getSuperclass(current);
    }
}

#pragma mark - Object inspection

static void IARInspectObject(id object,
                             NSString *label) {

    if (!object) {
        IARLog(@"%@ = NIL", label);
        return;
    }

    Class cls = object_getClass(object);

    IARLog(@"");
    IARLog(@"OBJECT: %@", label);
    IARLog(@"Description: %@", object);
    IARLog(@"Class: %@", NSStringFromClass(cls));

    IARDumpHierarchy(cls);
    IARDumpMethodsForClass(cls);
}

#pragma mark - Find classes

static void IARInspectClasses(void) {

    NSArray *classNames = @[
        @"SBIconController",
        @"SBHIconManager",
        @"SBIconModel",
        @"SBRootFolder",
        @"SBFolder",
        @"SBIcon",
        @"SBApplicationIcon",
        @"SBHIcon",
        @"SBHIconModel",
        @"SBHRootFolder"
    ];

    IARLog(@"");
    IARLog(@"================================");
    IARLog(@"CLASS AVAILABILITY");
    IARLog(@"================================");

    for (NSString *name in classNames) {

        Class cls =
            NSClassFromString(name);

        if (cls) {
            IARLog(@"FOUND: %@", name);
        } else {
            IARLog(@"NOT FOUND: %@", name);
        }
    }
}

#pragma mark - Main diagnostic

static void IARRunDiagnostic(void) {

    IARLog(@"");
    IARLog(@"################################");
    IARLog(@"ICON AUTO REFRESH DIAGNOSTIC");
    IARLog(@"################################");

    IARInspectClasses();

    Class controllerClass =
        NSClassFromString(@"SBIconController");

    if (!controllerClass) {
        IARLog(@"SBIconController NOT FOUND");
        return;
    }

    IARLog(@"");
    IARLog(@"Getting SBIconController.sharedInstance");

    id controller = nil;

    SEL sharedSelector =
        NSSelectorFromString(@"sharedInstance");

    if ([controllerClass respondsToSelector:sharedSelector]) {

        IMP imp =
            [controllerClass methodForSelector:sharedSelector];

        id (*func)(id, SEL) =
            (id (*)(id, SEL))imp;

        controller =
            func(controllerClass, sharedSelector);
    }

    IARInspectObject(controller,
                     @"SBIconController");

    if (!controller) {
        IARLog(@"Controller is NIL");
        return;
    }

    #pragma mark Icon Manager

    SEL managerSelector =
        NSSelectorFromString(@"iconManager");

    id iconManager = nil;

    if ([controller respondsToSelector:managerSelector]) {

        IMP imp =
            [controller methodForSelector:managerSelector];

        id (*func)(id, SEL) =
            (id (*)(id, SEL))imp;

        iconManager =
            func(controller, managerSelector);
    }

    IARInspectObject(iconManager,
                     @"SBHIconManager");

    #pragma mark Icon Model

    id iconModel = nil;

    SEL modelSelector =
        NSSelectorFromString(@"iconModel");

    if (iconManager &&
        [iconManager respondsToSelector:modelSelector]) {

        IMP imp =
            [iconManager methodForSelector:modelSelector];

        id (*func)(id, SEL) =
            (id (*)(id, SEL))imp;

        iconModel =
            func(iconManager, modelSelector);
    }

    IARInspectObject(iconModel,
                     @"SBIconModel");

    #pragma mark Root Folder

    id rootFolder = nil;

    SEL rootSelector =
        NSSelectorFromString(@"rootFolder");

    if (iconManager &&
        [iconManager respondsToSelector:rootSelector]) {

        IMP imp =
            [iconManager methodForSelector:rootSelector];

        id (*func)(id, SEL) =
            (id (*)(id, SEL))imp;

        rootFolder =
            func(iconManager, rootSelector);
    }

    IARInspectObject(rootFolder,
                     @"SBRootFolder");

    #pragma mark Important selectors

    IARLog(@"");
    IARLog(@"================================");
    IARLog(@"IMPORTANT SELECTOR CHECK");
    IARLog(@"================================");

    NSArray *selectors = @[
        @"addNewIconToFirstAvailablePage:animate:",
        @"addIcon:",
        @"addIcon:toFolder:",
        @"addIcon:toRootFolder:",
        @"insertIcon:",
        @"insertIcon:atIndex:",
        @"insertIcon:intoFolder:",
        @"addApplicationIconForBundleIdentifier:",
        @"expectedIconForDisplayIdentifier:",
        @"applicationIconForBundleIdentifier:",
        @"saveIconState",
        @"save",
        @"saveState",
        @"commit",
        @"reload",
        @"refresh",
        @"updateIconState",
        @"setIconState:",
        @"setDesiredIconState:"
    ];

    NSArray *objects = @[
        controller ?: [NSNull null],
        iconManager ?: [NSNull null],
        iconModel ?: [NSNull null],
        rootFolder ?: [NSNull null]
    ];

    for (id object in objects) {

        if (object == [NSNull null]) {
            continue;
        }

        IARLog(@"");
        IARLog(@"Object: %@",
               NSStringFromClass(object_getClass(object)));

        for (NSString *selectorName in selectors) {

            SEL sel =
                NSSelectorFromString(selectorName);

            BOOL responds =
                [object respondsToSelector:sel];

            if (responds) {
                IARLog(@"FOUND: %@", selectorName);
            }
        }
    }

    IARLog(@"");
    IARLog(@"################################");
    IARLog(@"DIAGNOSTIC FINISHED");
    IARLog(@"################################");
}

#pragma mark - Constructor

%ctor {

    IARLog(@"");
    IARLog(@"================================");
    IARLog(@"IconAutoRefresh loaded");
    IARLog(@"================================");

    /*
     * Wait until SpringBoard has finished creating
     * SBIconController / SBHIconManager.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(5 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            IARLog(@"Starting runtime diagnostic");

            IARRunDiagnostic();
        }
    );
}
