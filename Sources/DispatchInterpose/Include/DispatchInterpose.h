#if defined(__APPLE__) || defined(__MACH__)

//
//  DispatchInterpose.h
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

#pragma once
#include <dispatch/dispatch.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void swift_async_hooks_install(void);

#ifdef __cplusplus
}
#endif

#endif // __APPLE__ || __MACH__
