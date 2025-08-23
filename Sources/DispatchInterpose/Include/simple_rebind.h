#if defined(__APPLE__) || defined(__MACH__)

// simple_rebind.h
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct rebinding {
  const char *name;     // e.g. "dispatch_async"
  void *replacement;    // your replacement function
  void **replaced;      // out: original function (may be NULL)
};

// Rebind all symbols in all loaded images.
int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);

#ifdef __cplusplus
}
#endif

#endif // __APPLE__ || __MACH__
