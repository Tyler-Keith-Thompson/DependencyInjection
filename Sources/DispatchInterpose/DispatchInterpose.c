#include "simple_rebind.h"
#include "DispatchInterpose.h"

#if defined(DEBUG) && (defined(__APPLE__) || defined(__MACH__))

#include <dispatch/dispatch.h>
#include <pthread.h>

//
//  DispatchInterpose.c
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

// Swift shim that wraps the block (only available on Darwin)
extern void *di_transformBlock(void *block);

// Pointer to original function
static void (*orig_async)(void *group, void *qos, void *flags, void *block);
static void (*orig_async_after)(void *deadline, void *qos, void *flags, void *block);

// Our replacement
static void new_async(void *group, void *qos, void *flags, void *block) {
    void *wrapped = di_transformBlock(block);
    orig_async(group, qos, flags, wrapped);
}

static void new_async_after(void *deadline, void *qos, void *flags, void *block) {
    void *wrapped = di_transformBlock(block);
    orig_async_after(deadline, qos, flags, wrapped);
}

// Thread-safe deferred installer using pthread_once instead of dispatch_once
static pthread_once_t once_control = PTHREAD_ONCE_INIT;

static void install_hooks(void) {
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
}

void swift_async_hooks_install(void) {
    pthread_once(&once_control, install_hooks);
}

#else
// Non-Darwin platforms - provide stub implementation
void swift_async_hooks_install(void) {
    // No-op on non-Darwin platforms
}

#endif // DEBUG && (__APPLE__ || __MACH__)
