/*
 * Copyright 2018, Red Hat, Inc.
 *
 * Description: Make sure we can pass the MAP_SYNC flag to device dax
 * mappings.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/mman.h>
#include <libgen.h>

#ifndef MAP_SYNC
#define MAP_SYNC		0x80000
#define MAP_SHARED_VALIDATE	0x03
#endif

unsigned long
parse_size(char *arg)
{
	unsigned long size;
	char *suffix;

	size = strtoul(arg, &suffix, 0);
	while (*suffix == ' ')
		suffix++;

	if (*suffix != 0) {
		switch (*suffix) {
		case 'k':
		case 'K':
			size *= 1024;
			break;
		case 'm':
		case 'M':
			size *= 1024 * 1024;
			break;
		case 'g':
		case 'G':
			size *= 1024 * 1024 * 1024;
			break;
		default:
			printf("Invalid alignment specified: %s\n", arg);
			exit(1);
		}
	}

	return size;
}

int
main(int argc, char **argv)
{
	int fd;
	void *addr;
	unsigned long alignment;

	if (argc < 3) {
		printf("Usage: %s <dax dev> <alignment>\n", basename(argv[0]));
		exit(1);
	}

	alignment = parse_size(argv[2]);

	fd = open(argv[1], O_RDONLY);
	if (fd < 0) {
		perror("open");
		exit(1);
	}

	addr = mmap(NULL, alignment, PROT_READ,
		    MAP_SHARED | MAP_SYNC | MAP_SHARED_VALIDATE, fd, 0);
	if (addr == MAP_FAILED) {
		printf("mmap(MAP_SYNC) on device dax failed with %d\n", errno);
		exit(1);
	}

	printf("Success!\n");
	exit(0);
}
