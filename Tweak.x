#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
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

    NSString *message =
        [[NSString alloc]
            initWithFormat:format
            arguments:args];

    va_end(args);

    NSString *line =
        [NSString stringWithFormat:
            @"[%@] %@\n",
            [NSDate date],
            message];

    NSFileHandle *file =
        [NSFileHandle
            fileHandleForWritingAtPath:IARLogPath()];

    if (!file)
    {
        [[NSFileManager defaultManager]
            createFileAtPath:IARLogPath()
            contents:nil
            attributes:nil];

        file =
            [NSFileHandle
                fileHandleForWritingAtPath:IARLogPath()];
    }

    if (!file)
        return;

    [file seekToEndOfFile];

    [file writeData:
        [line dataUsingEncoding:NSUTF8StringEncoding]];

    [file closeFile];
}

static void IARDumpClass(Class cls)
{
    if (!cls)
        return;

    IARLog(
        @"========================================"
    );

    IARLog(
        @"CLASS: %@",
        NSStringFromClass(cls)
    );

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(
            cls,
            &count
        );

    IARLog(
        @"INSTANCE METHODS: %u",
        count
    );

    for (unsigned int i = 0; i < count; i++)
    {
        Method method = methods[i];

        SEL selector =
            method_getName(method);

        const char *types =
            method_getTypeEncoding(method);

        IARLog(
            @"INSTANCE: %@ | %s",
            NSStringFromSelector(selector),
            types ? types : "?"
        );
    }

    free(methods);

    count = 0;

    Method *classMethods =
        class_copyMethodList(
            object_getClass(cls),
            &count
        );

    IARLog(
        @"CLASS METHODS: %u",
        count
    );

    for (unsigned int i = 0; i < count; i++)
    {
        Method method = classMethods[i];

        SEL selector =
            method_getName(method);

        const char *types =
            method_getTypeEncoding(method);

        IARLog(
            @"CLASS: %@ | %s",
            NSStringFromSelector(selector),
            types ? types : "?"
        );
    }

    free(classMethods);

    Class superclass =
        class_getSuperclass(cls);

    if (superclass)
    {
        IARLog(
            @"SUPERCLASS: %@",
            NSStringFromClass(superclass)
        );

        IARDumpClass(superclass);
    }
}

static void IARDumpInterestingSelectors(Class cls)
{
    if (!cls)
        return;

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(
            cls,
            &count
        );

    for (unsigned int i = 0; i < count; i++)
    {
        SEL selector =
            method_getName(methods[i]);

        NSString *name =
            NSStringFromSelector(selector);

        NSArray *keywords = @[
            @"reload",
            @"update",
            @"layout",
            @"icon",
            @"application",
            @"folder",
            @"add",
            @"remove",
            @"arrange",
            @"edit",
            @"model",
            @"refresh",
            @"rebuild",
            @"display",
            @"homeScreen",
            @"homescreen"
        ];

        for (NSString *keyword in keywords)
        {
            if ([name rangeOfString:
                    keyword
                    options:NSCaseInsensitiveSearch].location
                != NSNotFound)
            {
                const char *types =
                    method_getTypeEncoding(methods[i]);

                IARLog(
                    @"INTERESTING %@ -> %@ | %s",
                    NSStringFromClass(cls),
                    name,
                    types ? types : "?"
                );

                break;
            }
        }
    }

    free(methods);

    Class superclass =
        class_getSuperclass(cls);

    if (superclass)
        IARDumpInterestingSelectors(superclass);
}

static void IARStartDiagnostics(void)
{
    IARLog(@"========================================");
    IARLog(@"IconAutoRefresh METHOD DUMP");
    IARLog(
        @"iOS: %@",
        UIDevice.currentDevice.systemVersion
    );
    IARLog(@"========================================");

    NSArray *classNames = @[
        @"SBIconController",
        @"SBIconModel",
        @"SBHIconManager",
        @"SBRootFolder",
        @"SBFolder"
    ];

    for (NSString *className in classNames)
    {
        Class cls =
            NSClassFromString(className);

        if (!cls)
        {
            IARLog(
                @"CLASS NOT FOUND: %@",
                className
            );

            continue;
        }

        IARLog(
            @"FOUND CLASS: %@",
            className
        );

        IARDumpClass(cls);

        IARLog(
            @"INTERESTING METHODS FOR %@",
            className
        );

        IARDumpInterestingSelectors(cls);
    }

    IARLog(@"========================================");
    IARLog(@"METHOD DUMP COMPLETE");
    IARLog(@"========================================");
}

%ctor
{
    @autoreleasepool
    {
        NSString *processName =
            [NSProcessInfo processInfo].processName;

        if (![processName
              isEqualToString:@"SpringBoard"])
        {
            return;
        }

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(3.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                IARStartDiagnostics();
            }
        );
    }
}
