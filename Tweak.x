#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
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

static BOOL IARShouldLogSelector(SEL selector)
{
    NSString *name =
        NSStringFromSelector(selector);

    NSArray *keywords = @[
        @"reload",
        @"update",
        @"layout",
        @"icon",
        @"application",
        @"model",
        @"folder",
        @"add",
        @"remove",
        @"rebuild",
        @"refresh",
        @"edit",
        @"arrange",
        @"save"
    ];

    for (NSString *keyword in keywords)
    {
        if ([name rangeOfString:
                keyword
                options:NSCaseInsensitiveSearch].location
            != NSNotFound)
        {
            return YES;
        }
    }

    return NO;
}

static void IARInstallHooksForClass(Class cls)
{
    if (!cls)
        return;

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(
            cls,
            &count
        );

    if (!methods)
        return;

    for (unsigned int i = 0; i < count; i++)
    {
        Method method = methods[i];

        SEL selector =
            method_getName(method);

        if (!IARShouldLogSelector(selector))
            continue;

        const char *types =
            method_getTypeEncoding(method);

        if (!types)
            continue;

        if (types[0] != 'v')
            continue;

        if (strstr(types, "@:") == NULL)
            continue;

        IMP originalIMP =
            method_getImplementation(method);

        NSString *selectorName =
            NSStringFromSelector(selector);

        IMP blockIMP =
            imp_implementationWithBlock(
                ^(id object)
                {
                    IARLog(
                        @"CALL %@ [%@]",
                        selectorName,
                        NSStringFromClass(
                            object_getClass(object)
                        )
                    );

                    ((void (*)(id, SEL))originalIMP)(
                        object,
                        selector
                    );
                }
            );

        method_setImplementation(
            method,
            blockIMP
        );
    }

    free(methods);
}

static void IARInstallHooks(void)
{
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
            @"HOOKING CLASS: %@",
            className
        );

        IARInstallHooksForClass(cls);
    }

    IARLog(@"HOOK INSTALLATION COMPLETE");
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
                (int64_t)(5.0 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                IARLog(@"================================");
                IARLog(@"IconAutoRefresh DEBUG STARTED");
                IARLog(@"iOS: %@", UIDevice.currentDevice.systemVersion);
                IARLog(@"================================");

                IARInstallHooks();
            }
        );
    }
}
