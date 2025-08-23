//
//  DispatchInterpose.h
//  DependencyInjection
//
//  Created by Tyler Thompson on 8/22/25.
//

#pragma once

#if defined(__APPLE__) || defined(__MACH__)
#include <dispatch/dispatch.h>
#endif

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void swift_async_hooks_install(void);

#ifdef __cplusplus
}
#endif
