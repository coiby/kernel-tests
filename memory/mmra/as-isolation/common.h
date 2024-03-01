// SPDX-License-Identifier: ISC
/**
 *  commom macro definitions for generic test programs
 *
 * Copyright (c) Rafael Aquini <aquini@redhat.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
#ifndef COMMON_H
#define COMMON_H

#include <errno.h>

#define PRINT_ERROR(msg)						   \
	do {								   \
		char *estr;						   \
		asprintf(&estr, "[%s:%d] %s: %s (%d)",			   \
			 __FILE__, __LINE__, msg, strerror(errno), errno); \
		fprintf(stderr, "%s\n", estr);				   \
		fflush(stderr);						   \
		free(estr);						   \
	} while (0)

#define ERROR_EXIT(msg)						\
	do {							\
		PRINT_ERROR(msg);				\
		exit(errno ? errno : EXIT_FAILURE);		\
	} while (0)

#define ERROR_WARN(msg) do { PRINT_ERROR(msg); } while (0)

#ifdef DEBUG
#define DPRINTF(...)						\
	do {							\
		fprintf(stderr, __VA_ARGS__);			\
		fflush(stderr);					\
	} while (0)
#else
#define DPRINTF(...)
#endif

#endif /* COMMON_H */
