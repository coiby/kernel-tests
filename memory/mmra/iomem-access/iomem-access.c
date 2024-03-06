/*
 * Copyright (C) 2024, Pablo Ridolfi <pridolfi@redhat.com>
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
 *
 * compile with:
 *   gcc -o iomem-access -D_GNU_SOURCE iomem-access.c
 *
 * usage:
 *   ./iomem-access addr_start_hex addr_end_hex # address range for the peripheral
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/mman.h>

int main(int argc, char *argv[])
{
	if (argc < 3) {
		fprintf(stderr, "wrong arguments\n");
		exit(EXIT_FAILURE);
	}
	
	unsigned long * addr_start = (unsigned long *)strtoul(argv[1], NULL, 16);
	unsigned long * addr_end = (unsigned long *)strtoul(argv[2], NULL, 16);
	size_t addr_size = (size_t)(addr_end - addr_start);

	int fd = open("/dev/mem", O_RDWR);
	if (-1 == fd) {
		perror("open /dev/mem");
		exit(EXIT_FAILURE);
	}

	unsigned long * ptr = mmap(0, addr_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)addr_start);
	if ((unsigned long *)-1 == ptr) {
		perror("mmap");
		exit(EXIT_FAILURE);
	}

	printf("Attempt to read from addr 0x%08X (mapped to 0x%08X)... ", addr_start, ptr);
	unsigned long io_value = *ptr;
	printf("read 0x%08X.\n", io_value);

	printf("Attempt to write 0x%0X to addr 0x%08X (mapped to 0x%08X)... ", io_value, addr_start, ptr);
	*ptr = io_value;
	printf("OK\n");

	if (-1 == munmap(ptr, addr_size)) {
		perror("munmap");
		exit(EXIT_FAILURE);
	}

	exit(EXIT_SUCCESS);
}
