/* Named management settings (`dutctl set IP NAME VALUE`) -> MGMT key and
 * value bytes. Shared by `dutctl set`, the [board DNA] sections of
 * duts.conf (issue 0066: validated when the file is parsed) and
 * `dutctl apply` / `dutctl keeper`.
 *
 * LGPL-2.1-or-later. */
#ifndef DUTSET_H
#define DUTSET_H

#include <stddef.h>
#include <stdint.h>

#define DS_MAX_VALUE 18

enum { DS_OK = 0, DS_UNKNOWN_NAME = -1, DS_BAD_VALUE = -2 };

/* Encode setting name = value. On DS_OK *key and val[0..*vlen) hold the
 * MGMT_SET key and value; otherwise *why (if non-NULL) is a short reason.
 * Numbers take C syntax (0x.., decimal) and must fit the key's width;
 * baud is converted to the UART NCO increment. */
int ds_encode(const char *name, const char *value, uint16_t *key, uint8_t val[DS_MAX_VALUE],
              uint16_t *vlen, const char **why);

/* The known setting names, NULL-terminated (for help and tests). */
extern const char *const ds_names[];

#endif
