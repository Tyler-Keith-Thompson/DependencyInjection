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
#include <stdint.h>

// Define dispatch types for Linux (these might not be available in headers)
typedef struct dispatch_queue_s *dispatch_queue_t;
typedef void (*dispatch_function_t)(void *);
typedef unsigned long long dispatch_time_t;

// We'll use dlsym to get the real functions

// Function pointers to the real libdispatch functions
static void (*real_dispatch_async)(dispatch_queue_t queue, void *block);
static void (*real_dispatch_async_f)(dispatch_queue_t queue, void *context, dispatch_function_t work);
static void (*real_dispatch_after_f)(dispatch_time_t when, dispatch_queue_t queue, void *context, dispatch_function_t work);

// External declarations for Swift bridge functions (will be resolved by linker)
extern void* getCurrentContainer(void);
extern void executeWithContainer(void* containerPtr, dispatch_function_t originalWork, void* context);
extern void* transformBlockWithContainer(void* containerPtr, void* block);

// C-based block registry to keep Swift blocks alive
#define MAX_BLOCKS 1024
static void* block_registry[MAX_BLOCKS];
static int next_block_id = 1;
static pthread_mutex_t registry_mutex = PTHREAD_MUTEX_INITIALIZER;

// Store a block in the registry and return its ID
static int store_block(void* block) {
    pthread_mutex_lock(&registry_mutex);
    
    if (next_block_id >= MAX_BLOCKS) {
        printf("❌ Block registry full!\n");
        fflush(stdout);
        pthread_mutex_unlock(&registry_mutex);
        return 0;
    }
    
    int block_id = next_block_id++;
    block_registry[block_id] = block;
    
    printf("🔄 Stored block %p with ID: %d\n", block, block_id);
    fflush(stdout);
    
    pthread_mutex_unlock(&registry_mutex);
    return block_id;
}

// Get a block from the registry by ID
static void* get_block(int block_id) {
    pthread_mutex_lock(&registry_mutex);
    
    if (block_id <= 0 || block_id >= MAX_BLOCKS) {
        printf("❌ Invalid block ID: %d\n", block_id);
        fflush(stdout);
        pthread_mutex_unlock(&registry_mutex);
        return NULL;
    }
    
    void* block = block_registry[block_id];
    pthread_mutex_unlock(&registry_mutex);
    
    return block;
}



// Wrapper context structure
struct wrapper_context {
    void* containerPtr;
    dispatch_function_t originalWork;
    void* originalContext;
};

// Wrapper work function that calls Swift to execute with container context
static void container_wrapper_work(void* ctx) {
    struct wrapper_context* wrapper = (struct wrapper_context*)ctx;
    
    printf("🔄 container_wrapper_work() called, executing with Swift\n");
    fflush(stdout);
    
    executeWithContainer(wrapper->containerPtr, wrapper->originalWork, wrapper->originalContext);
    
    printf("🔄 container_wrapper_work() completed, cleaning up\n");
    fflush(stdout);
    
    free(wrapper);
}



// Our interposed dispatch_async function - this will be called instead of the real one
void dispatch_async(dispatch_queue_t queue, void *block) {
    printf("🎯 dispatch_async() intercepted on Linux!\n");
    fflush(stdout);
    
    // Get the current container from Swift
    printf("🔍 Getting current container from Swift\n");
    fflush(stdout);
    
    void* containerPtr = getCurrentContainer();
    printf("🔍 Got container: %p\n", containerPtr);
    fflush(stdout);
    
    // Transform the block to preserve container context
    void* wrappedBlock = transformBlockWithContainer(containerPtr, block);
    printf("🔍 Got wrapped block: %p\n", wrappedBlock);
    fflush(stdout);
    
    // Store the wrapped block in our C registry to keep it alive
    int block_id = store_block(wrappedBlock);
    if (block_id == 0) {
        printf("❌ Failed to store block in registry!\n");
        fflush(stdout);
        return;
    }
    
    // Call the real dispatch_async with our wrapped block
    if (real_dispatch_async) {
        printf("🔍 Calling real dispatch_async with wrapped block\n");
        fflush(stdout);
        real_dispatch_async(queue, wrappedBlock);
    } else {
        printf("❌ real_dispatch_async is NULL!\n");
        fflush(stdout);
    }
}

// Our interposed dispatch_async_f function - this will be called instead of the real one
void dispatch_async_f(dispatch_queue_t queue, void *context, dispatch_function_t work) {
    printf("🎯 dispatch_async_f() intercepted on Linux!\n");
    fflush(stdout);
    
    // Get the current container from Swift
    printf("🔍 Getting current container from Swift\n");
    fflush(stdout);
    
    void* containerPtr = getCurrentContainer();
    printf("🔍 Got container: %p\n", containerPtr);
    fflush(stdout);
    
    // Create wrapper context
    struct wrapper_context* wrapper = malloc(sizeof(struct wrapper_context));
    wrapper->containerPtr = containerPtr;
    wrapper->originalWork = work;
    wrapper->originalContext = context;
    
    // Call the real function with our wrapper
    if (real_dispatch_async_f) {
        real_dispatch_async_f(queue, wrapper, container_wrapper_work);
    } else {
        printf("❌ real_dispatch_async_f is NULL! Calling work directly to avoid hang\n");
        fflush(stdout);
        // Fallback: call the wrapper work function directly
        container_wrapper_work(wrapper);
    }
}



// Our interposed dispatch_after_f function - this will be called instead of the real one
void dispatch_after_f(dispatch_time_t when, dispatch_queue_t queue, void *context, dispatch_function_t work) {
    printf("🎯 dispatch_after_f() intercepted on Linux!\n");
    fflush(stdout);
    
    // Get the current container from Swift
    printf("🔍 Getting current container from Swift\n");
    fflush(stdout);
    
    void* containerPtr = getCurrentContainer();
    printf("🔍 Got container: %p\n", containerPtr);
    fflush(stdout);
    
    // Create wrapper context
    struct wrapper_context* wrapper = malloc(sizeof(struct wrapper_context));
    wrapper->containerPtr = containerPtr;
    wrapper->originalWork = work;
    wrapper->originalContext = context;
    
    // Call the real function with our wrapper
    if (real_dispatch_after_f) {
        real_dispatch_after_f(when, queue, wrapper, container_wrapper_work);
    } else {
        printf("❌ real_dispatch_after_f is NULL! Calling work directly to avoid hang\n");
        fflush(stdout);
        // Fallback: call the wrapper work function directly
        container_wrapper_work(wrapper);
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
    
               // Use RTLD_NEXT to get the real functions (not our interposed ones)
           real_dispatch_async = dlsym(RTLD_NEXT, "dispatch_async");
           real_dispatch_async_f = dlsym(RTLD_NEXT, "dispatch_async_f");
           real_dispatch_after_f = dlsym(RTLD_NEXT, "dispatch_after_f");
           
           printf("🔧 real_dispatch_async: %p\n", real_dispatch_async);
           printf("🔧 real_dispatch_async_f: %p\n", real_dispatch_async_f);
           printf("🔧 real_dispatch_after_f: %p\n", real_dispatch_after_f);
           fflush(stdout);
           
           if (!real_dispatch_async || !real_dispatch_async_f || !real_dispatch_after_f) {
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
