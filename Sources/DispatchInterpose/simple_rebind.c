#include "simple_rebind.h"

#if defined(__APPLE__) || defined(__MACH__)

#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/vm_page_size.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <os/lock.h>
#include <string.h>
#include <stdlib.h>

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

#ifndef SEG_DATA_CONST
#define SEG_DATA_CONST "__DATA_CONST"
#endif

// ----- global (heap-copied) table + lock -----
static struct rebinding *g_rebindings = NULL;
static size_t g_rebindings_nel = 0;
static os_unfair_lock g_lock = OS_UNFAIR_LOCK_INIT;

// Make the whole section containing stubs writable (page-aligned)
static inline void make_section_writable(void *section_base, size_t section_size) {
  vm_address_t addr = (vm_address_t)section_base;
  vm_size_t len = (vm_size_t)section_size;
  // vm_protect expects page-aligned, but will round; we pass the section base.
  (void)vm_protect(mach_task_self(), addr, len, /*set_max_protection*/ 0,
                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
}

static void rebind_section(struct rebinding *rebindings,
                           size_t rebindings_nel,
                           section_t *sect,
                           intptr_t slide,
                           nlist_t *symtab,
                           size_t nsyms,
                           char *strtab,
                           size_t strtab_size,
                           uint32_t *indirect_symtab) {
  uint32_t *indirect_syms = indirect_symtab + sect->reserved1;
  void **indirect_bindings_base = (void **)((uintptr_t)slide + sect->addr);

  // Ensure we can patch pointers in this section (once per section)
  make_section_writable(indirect_bindings_base, (size_t)sect->size);

  size_t count = (size_t)(sect->size / sizeof(void *));
  for (size_t i = 0; i < count; i++) {
    uint32_t sym_index = indirect_syms[i];
    if (sym_index == INDIRECT_SYMBOL_ABS ||
        sym_index == INDIRECT_SYMBOL_LOCAL ||
        sym_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
      continue;
    }
    if ((size_t)sym_index >= nsyms) continue;

    uint32_t strx = symtab[sym_index].n_un.n_strx;
    if (strx == 0 || (size_t)strx >= strtab_size) continue;

    const char *symname = strtab + strx;
    size_t maxlen = strtab_size - (size_t)strx;
    if (maxlen == 0 || symname[0] != '_') continue;

    for (size_t j = 0; j < rebindings_nel; j++) {
      const char *target = rebindings[j].name;
      if (!target) continue;

      // Bound compare to avoid walking off malformed string tables.
      if (strncmp(symname + 1, target, maxlen - 1) == 0) {
        void **slot = &indirect_bindings_base[i];

        if (rebindings[j].replaced && *rebindings[j].replaced == NULL) {
          *rebindings[j].replaced = *slot;
        }
        *slot = rebindings[j].replacement;
        goto next_symbol;
      }
    }
  next_symbol:;
  }
}

static void rebind_image(const struct mach_header *header,
                         intptr_t slide,
                         struct rebinding *rebindings,
                         size_t rebindings_nel) {
  if (!rebindings || rebindings_nel == 0) return;

  segment_command_t *cur_seg = NULL;
  segment_command_t *linkedit = NULL;
  struct symtab_command *symtab_cmd = NULL;
  struct dysymtab_command *dysymtab_cmd = NULL;

  uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
  for (unsigned int i = 0; i < header->ncmds; i++, cur += cur_seg->cmdsize) {
    cur_seg = (segment_command_t *)cur;
    if (cur_seg->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
      if (strcmp(cur_seg->segname, SEG_LINKEDIT) == 0) {
        linkedit = cur_seg;
      }
    } else if (cur_seg->cmd == LC_SYMTAB) {
      symtab_cmd = (struct symtab_command *)cur_seg;
    } else if (cur_seg->cmd == LC_DYSYMTAB) {
      dysymtab_cmd = (struct dysymtab_command *)cur_seg;
    }
  }
  if (!symtab_cmd || !dysymtab_cmd || !linkedit || dysymtab_cmd->nindirectsyms == 0) return;

  uintptr_t linkedit_base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
  nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
  char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
  size_t strtab_size = symtab_cmd->strsize;
  uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

  cur = (uintptr_t)header + sizeof(mach_header_t);
  for (unsigned int i = 0; i < header->ncmds; i++, cur += cur_seg->cmdsize) {
    cur_seg = (segment_command_t *)cur;
    if (cur_seg->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
      if (strcmp(cur_seg->segname, SEG_DATA) != 0 &&
          strcmp(cur_seg->segname, SEG_DATA_CONST) != 0) {
        continue;
      }
      section_t *sects = (section_t *)(cur + sizeof(segment_command_t));
      for (unsigned int j = 0; j < cur_seg->nsects; j++) {
        uint32_t type = sects[j].flags & SECTION_TYPE;
        if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
          rebind_section(rebindings, rebindings_nel, &sects[j], slide,
                         symtab, symtab_cmd->nsyms,
                         strtab, strtab_size,
                         indirect_symtab);
        }
      }
    }
  }
}

// dyld callback
static void dyld_callback(const struct mach_header *h, intptr_t slide) {
  os_unfair_lock_lock(&g_lock);
  struct rebinding *local = g_rebindings;
  size_t nel = g_rebindings_nel;
  os_unfair_lock_unlock(&g_lock);

  if (local && nel) {
    rebind_image(h, slide, local, nel);
  }
}

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
  if (!rebindings || rebindings_nel == 0) return 0;

  // Copy table to heap so we don't depend on caller's lifetime
  struct rebinding *copy = (struct rebinding *)malloc(rebindings_nel * sizeof(struct rebinding));
  if (!copy) return -1;
  memcpy(copy, rebindings, rebindings_nel * sizeof(struct rebinding));

  os_unfair_lock_lock(&g_lock);
  // Free previous (if any)
  if (g_rebindings) free(g_rebindings);
  g_rebindings = copy;
  g_rebindings_nel = rebindings_nel;
  os_unfair_lock_unlock(&g_lock);

  // Register once (idempotent: dyld allows multiple callbacks)
  static bool registered = false;
  static os_unfair_lock reg_lock = OS_UNFAIR_LOCK_INIT;
  os_unfair_lock_lock(&reg_lock);
  if (!registered) {
    _dyld_register_func_for_add_image(dyld_callback);
    registered = true;
  }
  os_unfair_lock_unlock(&reg_lock);

  // Apply immediately to already-loaded images
  uint32_t count = _dyld_image_count();
  for (uint32_t i = 0; i < count; i++) {
    rebind_image(_dyld_get_image_header(i),
                 _dyld_get_image_vmaddr_slide(i),
                 copy, rebindings_nel);
  }
  return 0;
}

#else
// Non-Darwin platforms - provide stub implementations
int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
    // No-op on non-Darwin platforms
    (void)rebindings;
    (void)rebindings_nel;
    return 0;
}

#endif // __APPLE__ || __MACH__
