#include "simple_rebind.h"
#include "DispatchInterpose.h"

#if defined(__APPLE__) || defined(__MACH__)

#include <dispatch/dispatch.h>
#include <pthread.h>

//
//  DispatchInterpose.c
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

// Swift shim that wraps the block (only available on Darwin)
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
// Linux: Implement using weak symbols and function pointer replacement
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>

// Define dispatch types for Linux (these might not be available in headers)
typedef struct dispatch_queue_s *dispatch_queue_t;
typedef void (*dispatch_function_t)(void *);
typedef unsigned long long dispatch_time_t;

// We'll use dlsym to get the real functions

// Function pointers to the real libdispatch functions
static void (*real_dispatch_async_f)(dispatch_queue_t queue, void *context, dispatch_function_t work);
static void (*real_dispatch_after_f)(dispatch_time_t when, dispatch_queue_t queue, void *context, dispatch_function_t work);

// External declarations for Swift bridge functions (will be resolved by linker)
extern void* get_current_container(void);
extern void set_current_container(void* containerPtr);

// Wrapper work function for async dispatch
static void async_wrapper_work(void *ctx) {
    printf("🔄 async_wrapper_work() called!\n");
    fflush(stdout);
    
    struct wrapper_context {
        void *original_context;
        void *container;
        dispatch_function_t original_work;
    };
    
    struct wrapper_context *wrapper = (struct wrapper_context *)ctx;
    
    printf("🔄 About to call set_current_container with: %p\n", wrapper->container);
    fflush(stdout);
    
    // Restore the container context using Swift function
    if (wrapper->container) {
        set_current_container(wrapper->container);
        printf("🔄 Called Swift set_current_container(%p)\n", wrapper->container);
    } else {
        printf("🔄 Container is NULL, skipping set_current_container\n");
    }
    fflush(stdout);
    
    printf("🔄 About to call original work function\n");
    fflush(stdout);
    
    // Call the original work function
    wrapper->original_work(wrapper->original_context);
    
    printf("🔄 Cleaning up wrapper\n");
    fflush(stdout);
    
    // Clean up
    free(wrapper);
}

// Our interposed dispatch_async_f function - this will be called instead of the real one
void dispatch_async_f(dispatch_queue_t queue, void *context, dispatch_function_t work) {
    printf("🎯 dispatch_async_f() intercepted on Linux!\n");
    fflush(stdout);
    
    // Get the current container context before the dispatch
    printf("🔍 About to call get_current_container()\n");
    fflush(stdout);
    
    void *container = get_current_container();
    printf("🔍 Swift get_current_container() returned: %p\n", container);
    fflush(stdout);
    
    // Create a wrapper context that includes both the original context and our container
    struct wrapper_context {
        void *original_context;
        void *container;
        dispatch_function_t original_work;
    };
    
    struct wrapper_context *wrapper = malloc(sizeof(struct wrapper_context));
    wrapper->original_context = context;
    wrapper->container = container;
    wrapper->original_work = work;
    
    // Call the real function with our wrapper
    if (real_dispatch_async_f) {
        real_dispatch_async_f(queue, wrapper, async_wrapper_work);
    } else {
        printf("❌ real_dispatch_async_f is NULL! Calling work directly to avoid hang\n");
        fflush(stdout);
        // Fallback: call the work function directly to avoid hanging
        work(context);
        free(wrapper);
    }
}

// Wrapper work function for after dispatch
static void after_wrapper_work(void *ctx) {
    struct wrapper_context {
        void *original_context;
        void *container;
        dispatch_function_t original_work;
    };
    
    struct wrapper_context *wrapper = (struct wrapper_context *)ctx;
    
    // Restore the container context
    set_current_container(wrapper->container);
    
    // Call the original work function
    wrapper->original_work(wrapper->original_context);
    
    // Clean up
    free(wrapper);
}

// Our interposed dispatch_after_f function - this will be called instead of the real one
void dispatch_after_f(dispatch_time_t when, dispatch_queue_t queue, void *context, dispatch_function_t work) {
    printf("🎯 dispatch_after_f() intercepted on Linux!\n");
    fflush(stdout);
    
    // Get the current container context before the dispatch
    void *container = get_current_container();
    
    // Create a wrapper context that includes both the original context and our container
    struct wrapper_context {
        void *original_context;
        void *container;
        dispatch_function_t original_work;
    };
    
    struct wrapper_context *wrapper = malloc(sizeof(struct wrapper_context));
    wrapper->original_context = context;
    wrapper->container = container;
    wrapper->original_work = work;
    
    // Call the real function with our wrapper
    if (real_dispatch_after_f) {
        real_dispatch_after_f(when, queue, wrapper, after_wrapper_work);
    } else {
        printf("❌ real_dispatch_after_f is NULL! Calling work directly to avoid hang\n");
        fflush(stdout);
        // Fallback: call the work function directly to avoid hanging
        work(context);
        free(wrapper);
    }
}

// Thread-safe installer using pthread_once
static pthread_once_t once_control = PTHREAD_ONCE_INIT;

static void install_linux_hooks(void) {
    printf("🔧 install_linux_hooks() called - setting up real function pointers\n");
    fflush(stdout);
    
    // Get function pointers to the real libdispatch functions
    // Try different possible library names
    void *libdispatch = NULL;
    const char *libnames[] = {
        "libdispatch.so",
        "libdispatch.so.0",
        "/usr/lib/swift/linux/libdispatch.so",
        NULL
    };
    
    for (int i = 0; libnames[i] != NULL; i++) {
        printf("🔍 Trying to open: %s\n", libnames[i]);
        fflush(stdout);
        libdispatch = dlopen(libnames[i], RTLD_LAZY);
        if (libdispatch) {
            printf("✅ Successfully opened: %s\n", libnames[i]);
            fflush(stdout);
            break;
        } else {
            printf("❌ Failed to open %s: %s\n", libnames[i], dlerror());
            fflush(stdout);
        }
    }
    
    if (!libdispatch) {
        printf("❌ Failed to open any libdispatch library!\n");
        fflush(stdout);
        return;
    }
    
    real_dispatch_async_f = dlsym(libdispatch, "dispatch_async_f");
    real_dispatch_after_f = dlsym(libdispatch, "dispatch_after_f");
    
    printf("🔧 real_dispatch_async_f: %p\n", real_dispatch_async_f);
    printf("🔧 real_dispatch_after_f: %p\n", real_dispatch_after_f);
    fflush(stdout);
    
    if (!real_dispatch_async_f || !real_dispatch_after_f) {
        printf("❌ Failed to find dispatch functions in libdispatch.so!\n");
        fflush(stdout);
        return;
    }
    

    printf("✅ Successfully set up interposition - our functions will now be called!\n");
    fflush(stdout);
}

void swift_async_hooks_install(void) {
    printf("🚀 swift_async_hooks_install() called on Linux!\n");
    fflush(stdout);
    pthread_once(&once_control, install_linux_hooks);
}

#endif // __APPLE__ || __MACH__
