//
//  DispatchInterpose.m
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

// DispatchInterpose.m
#import "simple_rebind.h"
#import "DispatchInterpose.h" // your header that declares swift_async_hooks_install

// Swift shim that wraps the block
extern void *transformBlock(void *block);

// Pointer to original function
static void (*orig_async)(void *group, void *qos, void *flags, void *block);
static void (*orig_async_after)(void *deadline, void *qos, void *flags, void *block);

// Our replacement
static void new_async(void *group, void *qos, void *flags, void *block) {
    void *wrapped = transformBlock(block);
    orig_async(group, qos, flags, wrapped);
}

static void new_async_after(void *deadline, void *qos, void *flags, void *block) {
    void *wrapped = transformBlock(block);
    orig_async_after(deadline, qos, flags, wrapped);
}

// Thread-safe deferred installer
void swift_async_hooks_install(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct rebinding rebindings[] = {
            {
                // async(group:qos:flags:execute:)
                "$sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF",
                (void *)new_async,
                (void **)&orig_async
            },
            {
                // asyncAfter(deadline:qos:flags:execute:)
                "$sSo17OS_dispatch_queueC8DispatchE10asyncAfter8deadline3qos5flags7executeyAC0D4TimeV_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF",
                (void *)new_async_after,
                (void **)&orig_async_after
            }
        };
        rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    });
}
