#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Logging

static NSString *const kIARLogPath =
    @"/var/mobile/IconAutoRefresh.log";

static void IARLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);

    NSString *message =
        [[NSString alloc] initWithFormat:format
                              arguments:args];

    va_end(args);

    NSLog(@"[IconAutoRefresh] %@", message);

    NSString *line =
        [NSString stringWithFormat:@"[%@] %@\n",
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

        NSData *data =
            [line dataUsingEncoding:NSUTF8StringEncoding];

        [handle writeData:data];
        [handle closeFile];
    }
}

#pragma mark - Method information

static NSString *IARTypeEncodingDescription(const char *types) {
    if (!types) {
        return @"(null)";
    }

    return [NSString stringWithUTF8String:types];
}

static BOOL IARMethodLooksInteresting(SEL selector) {

    NSString *name =
        NSStringFromSelector(selector).lowercaseString;

    NSArray<NSString *> *keywords = @[
        @"icon",
        @"add",
        @"insert",
        @"place",
        @"append",
        @"remove",
        @"delete",
        @"folder",
        @"page",
        @"model",
        @"layout",
        @"home",
        @"root",
        @"application",
        @"display",
        @"move",
        @"reorder",
        @"position",
        @"state",
        @"save",
        @"update",
        @"refresh",
        @"reload",
        @"install"
    ];

    for (NSString *keyword in keywords) {
        if ([name containsString:keyword]) {
            return YES;
        }
    }

    return NO;
}

#pragma mark - Dump class methods

static void IARDumpClassMethods(Class cls) {

    if (!cls) {
        return;
    }

    NSString *className =
        NSStringFromClass(cls);

    IARLog(@"");
    IARLog(@"========================================");
    IARLog(@"CLASS: %@", className);
    IARLog(@"========================================");

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(cls, &count);

    if (!methods) {
        IARLog(@"No instance methods returned");
        return;
    }

    NSMutableArray<NSString *> *interesting =
        [NSMutableArray array];

    NSMutableArray<NSString *> *all =
        [NSMutableArray array];

    for (unsigned int i = 0; i < count; i++) {

        Method method = methods[i];

        SEL selector =
            method_getName(method);

        const char *types =
            method_getTypeEncoding(method);

        NSString *entry =
            [NSString stringWithFormat:
                @"%@    [%@]",
                NSStringFromSelector(selector),
                IARTypeEncodingDescription(types)];

        [all addObject:entry];

        if (IARMethodLooksInteresting(selector)) {
            [interesting addObject:entry];
        }
    }

    free(methods);

    /*
     * First print interesting methods.
     */

    IARLog(@"INTERESTING METHODS: %lu",
           (unsigned long)interesting.count);

    for (NSString *entry in interesting) {
        IARLog(@"%@", entry);
    }

    /*
     * Then print the complete list.
     *
     * This is useful if the real insertion method has
     * an unexpected name.
     */

    IARLog(@"");
    IARLog(@"ALL INSTANCE METHODS: %lu",
           (unsigned long)all.count);

    for (NSString *entry in all) {
        IARLog(@"%@", entry);
    }
}

#pragma mark - Dump class hierarchy

static void IARDumpHierarchy(Class cls) {

    IARLog(@"");
    IARLog(@"========================================");
    IARLog(@"CLASS HIERARCHY");
    IARLog(@"========================================");

    Class current = cls;

    while (current) {

        IARLog(@"%@", NSStringFromClass(current));

        current =
            class_getSuperclass(current);
    }
}

#pragma mark - Dump protocol information

static void IARDumpProtocols(Class cls) {

    if (!cls) {
        return;
    }

    IARLog(@"");
    IARLog(@"========================================");
    IARLog(@"PROTOCOLS: %@", NSStringFromClass(cls));
    IARLog(@"========================================");

    unsigned int count = 0;

    Protocol *__unsafe_unretained *protocols =
        class_copyProtocolList(cls, &count);

    if (!protocols) {
        IARLog(@"No protocols");
        return;
    }

    for (unsigned int i = 0; i < count; i++) {

        Protocol *protocol =
            protocols[i];

        const char *name =
            protocol_getName(protocol);

        if (name) {
            IARLog(@"%@", [NSString stringWithUTF8String:name]);
        }
    }

    free(protocols);
}

#pragma mark - Dump class

static void IARDumpClass(NSString *name) {

    IARLog(@"");
    IARLog(@"########################################");
    IARLog(@"INSPECTING %@", name);
    IARLog(@"########################################");

    Class cls =
        NSClassFromString(name);

    if (!cls) {
        IARLog(@"CLASS NOT FOUND: %@", name);
        return;
    }

    IARLog(@"Class found: %@", cls);

    IARDumpHierarchy(cls);
    IARDumpProtocols(cls);
    IARDumpClassMethods(cls);
}

#pragma mark - Existing instance diagnostics

static void IARInspectLiveObjects(void) {

    IARLog(@"");
    IARLog(@"########################################");
    IARLog(@"LIVE SPRINGBOARD OBJECTS");
    IARLog(@"########################################");

    Class controllerClass =
        NSClassFromString(@"SBIconController");

    if (!controllerClass) {
        IARLog(@"SBIconController not found");
        return;
    }

    SEL sharedSelector =
        NSSelectorFromString(@"sharedInstance");

    if (![controllerClass respondsToSelector:sharedSelector]) {
        IARLog(@"sharedInstance unavailable");
        return;
    }

    id (*getShared)(id, SEL) =
        (id (*)(id, SEL))objc_msgSend;

    id controller =
        getShared(controllerClass,
                  sharedSelector);

    IARLog(@"SBIconController = %@", controller);

    if (!controller) {
        return;
    }

    SEL iconManagerSelector =
        NSSelectorFromString(@"iconManager");

    if ([controller respondsToSelector:iconManagerSelector]) {

        id (*getManager)(id, SEL) =
            (id (*)(id, SEL))objc_msgSend;

        id manager =
            getManager(controller,
                       iconManagerSelector);

        IARLog(@"SBHIconManager = %@", manager);

        if (manager) {

            SEL modelSelector =
                NSSelectorFromString(@"iconModel");

            if ([manager respondsToSelector:modelSelector]) {

                id (*getModel)(id, SEL) =
                    (id (*)(id, SEL))objc_msgSend;

                id model =
                    getModel(manager,
                             modelSelector);

                IARLog(@"SBIconModel = %@", model);
            }

            SEL rootSelector =
                NSSelectorFromString(@"rootFolder");

            if ([manager respondsToSelector:rootSelector]) {

                id (*getRoot)(id, SEL) =
                    (id (*)(id, SEL))objc_msgSend;

                id root =
                    getRoot(manager,
                            rootSelector);

                IARLog(@"SBRootFolder = %@", root);
            }
        }
    }
}

#pragma mark - Runtime class enumeration

static void IARFindRelatedClasses(void) {

    IARLog(@"");
    IARLog(@"########################################");
    IARLog(@"RELATED RUNTIME CLASSES");
    IARLog(@"########################################");

    int classCount =
        objc_getClassList(NULL, 0);

    if (classCount <= 0) {
        IARLog(@"objc_getClassList returned 0");
        return;
    }

    Class *classes =
        (__unsafe_unretained Class *)
        malloc(sizeof(Class) * classCount);

    if (!classes) {
        IARLog(@"Could not allocate class list");
        return;
    }

    classCount =
        objc_getClassList(classes,
                          classCount);

    NSArray<NSString *> *prefixes = @[
        @"SBIcon",
        @"SBHIcon",
        @"SBRoot",
        @"SBFolder",
        @"SBApplication",
        @"SBHome",
        @"SBPage"
    ];

    NSMutableArray<NSString *> *names =
        [NSMutableArray array];

    for (int i = 0; i < classCount; i++) {

        Class cls = classes[i];

        const char *cname =
            class_getName(cls);

        if (!cname) {
            continue;
        }

        NSString *name =
            [NSString stringWithUTF8String:cname];

        for (NSString *prefix in prefixes) {

            if ([name hasPrefix:prefix]) {
                [names addObject:name];
                break;
            }
        }
    }

    free(classes);

    [names sortUsingSelector:
        @selector(localizedCaseInsensitiveCompare:)];

    IARLog(@"Found %lu related classes",
           (unsigned long)names.count);

    for (NSString *name in names) {
        IARLog(@"%@", name);
    }
}

#pragma mark - Inspect selectors individually

static void IARCheckImportantSelectors(void) {

    IARLog(@"");
    IARLog(@"########################################");
    IARLog(@"IMPORTANT SELECTOR CHECK");
    IARLog(@"########################################");

    NSArray<NSDictionary *> *checks = @[
        @{
            @"class": @"SBIconModel",
            @"selectors": @[
                @"expectedIconForDisplayIdentifier:",
                @"applicationIconForBundleIdentifier:",
                @"addApplicationIconForBundleIdentifier:",
                @"addIcon:toFirstAvailablePage:",
                @"placeIcon:inRootFolder:",
                @"addIcon:",
                @"insertIcon:",
                @"insertIcon:atIndexPath:",
                @"addIcon:toFolder:",
                @"addIcon:toPage:",
                @"saveIconState",
                @"saveIconState:",
                @"reload",
                @"reloadIconState",
                @"updateIconState"
            ]
        },

        @{
            @"class": @"SBHIconManager",
            @"selectors": @[
                @"addNewIconToFirstAvailablePage:animate:",
                @"addIcon:toFirstAvailablePage:",
                @"addIcon:",
                @"insertIcon:",
                @"placeIcon:",
                @"addIconToHomeScreen:",
                @"saveIconState",
                @"reload"
            ]
        },

        @{
            @"class": @"SBIconController",
            @"selectors": @[
                @"addNewIconToFirstAvailablePage:animate:",
                @"addIcon:toFirstAvailablePage:",
                @"addIcon:",
                @"insertIcon:",
                @"placeIcon:",
                @"addIconToHomeScreen:",
                @"saveIconState"
            ]
        },

        @{
            @"class": @"SBRootFolder",
            @"selectors": @[
                @"containsIcon:",
                @"addIcon:",
                @"insertIcon:",
                @"removeIcon:",
                @"addIcon:atIndex:",
                @"insertIcon:atIndex:"
            ]
        }
    ];

    for (NSDictionary *check in checks) {

        NSString *className =
            check[@"class"];

        NSArray *selectors =
            check[@"selectors"];

        Class cls =
            NSClassFromString(className);

        IARLog(@"");
        IARLog(@"-- %@ --", className);

        if (!cls) {
            IARLog(@"Class not found");
            continue;
        }

        for (NSString *selectorName in selectors) {

            SEL selector =
                NSSelectorFromString(selectorName);

            BOOL instance =
                [cls instancesRespondToSelector:selector];

            BOOL classResponse =
                [cls respondsToSelector:selector];

            IARLog(@"%@  instance=%d class=%d",
                   selectorName,
                   instance,
                   classResponse);
        }
    }
}

#pragma mark - Main diagnostic

static void IARRunDiagnostics(void) {

    @autoreleasepool {

        IARLog(@"");
        IARLog(@"");
        IARLog(@"========================================");
        IARLog(@"ICON AUTO REFRESH");
        IARLog(@"FULL RUNTIME DIAGNOSTIC");
        IARLog(@"========================================");

        IARLog(@"iOS version: %@",
               UIDevice.currentDevice.systemVersion);

        IARLog(@"Device: %@",
               UIDevice.currentDevice.model);

        /*
         * Core classes.
         */

        IARDumpClass(@"SBIconModel");
        IARDumpClass(@"SBHIconManager");
        IARDumpClass(@"SBIconController");
        IARDumpClass(@"SBRootFolder");
        IARDumpClass(@"SBFolder");

        /*
         * Live SpringBoard objects.
         */

        IARInspectLiveObjects();

        /*
         * Check known candidates.
         */

        IARCheckImportantSelectors();

        /*
         * Find related runtime classes.
         */

        IARFindRelatedClasses();

        IARLog(@"");
        IARLog(@"========================================");
        IARLog(@"DIAGNOSTIC COMPLETE");
        IARLog(@"========================================");
    }
}

#pragma mark - Constructor

%ctor {

    @autoreleasepool {

        IARLog(@"");
        IARLog(@"==============================");
        IARLog(@"IconAutoRefresh diagnostic loaded");
        IARLog(@"==============================");

        /*
         * Wait until SpringBoard is fully initialized.
         */

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                5 * NSEC_PER_SEC
            ),
            dispatch_get_main_queue(),
            ^{
                IARRunDiagnostics();
            }
        );
    }
}
