/*
 * Copyright 2018, Red Hat, Inc.
 * License: GPLv2
 * Author: Jeff Moyer <jmoyer@redhat.com>
 *
 * Description: Device Dax instances (i.e. /dev/dax0.0) did not
 * advertise their MMUPageSize correctly in /proc/pid/smaps.  A patch
 * to rectify that appeared in kernel v4.17, introduced by commit
 * c1d53b92b95c.  This test verifies that the MMUPageSize is
 * correct for device dax mappings.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <libgen.h>
#include <fcntl.h>
#include <sys/mman.h>

#define LINE_SIZE 4096
#define PROCMAXLEN 2048 /* maximum expected line length in /proc files */

void
usage(char *prog)
{
	printf("Usage: %s <dax dev> <alignment>\n", basename(prog));
}

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

/*
 * Taken from the kernel: tools/testing/selftests/vm/mlock2.h.
 * License: GPLv2
 */
static FILE *seek_to_smaps_entry(unsigned long addr)
{
	FILE *file;
	char *line = NULL;
	size_t size = 0;
	unsigned long start, end;
	char perms[5];
	unsigned long offset;
	char dev[32];
	unsigned long inode;
	char path[BUFSIZ];

	file = fopen("/proc/self/smaps", "r");
	if (!file) {
		perror("fopen smaps");
		_exit(1);
	}

	while (getline(&line, &size, file) > 0) {
		if (sscanf(line, "%lx-%lx %s %lx %s %lu %s\n",
			   &start, &end, perms, &offset, dev, &inode, path) < 6)
			goto next;

		if (start <= addr && addr < end)
			goto out;

next:
		free(line);
		line = NULL;
		size = 0;
	}

	fclose(file);
	file = NULL;

out:
	free(line);
	return file;
}

/*
 * Taken from the kernel: tools/testing/selftests/vm/mlock-random-test.c.
 * License: GPLv2
 *
 * Get the MMUPageSize of the memory region including input
 * address from proc file.
 *
 * return value: on error case, 0 will be returned.
 * Otherwise the page size(in bytes) is returned.
 */
unsigned long get_proc_page_size(unsigned long addr)
{
	FILE *smaps;
	char *line = NULL;
	unsigned long mmupage_size = 0;
	size_t size;

	smaps = seek_to_smaps_entry(addr);
	if (!smaps) {
		printf("Unable to parse /proc/self/smaps\n");
		exit(1);
	}

	while (getline(&line, &size, smaps) > 0) {
		if (!strstr(line, "MMUPageSize")) {
			free(line);
			line = NULL;
			size = 0;
			continue;
		}

		/* found the MMUPageSize of this section */
		if (sscanf(line, "MMUPageSize:    %8lu kB",
					&mmupage_size) < 1) {
			printf("Unable to parse smaps entry for Size:%s\n",
					line);
			exit(1);
		}
		break;
	}
	free(line);
	if (smaps)
		fclose(smaps);
	return mmupage_size << 10;
}

int
main(int argc, char **argv)
{
	int fd;
	void *addr;
	unsigned long alignment;
	unsigned long mmu_pagesize;

	if (argc < 3) {
		usage(argv[0]);
		exit(1);
	}

	fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		perror("open");
		exit(1);
	}

	alignment = parse_size(argv[2]);

	addr = mmap(NULL, alignment, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
	if (addr == MAP_FAILED) {
		perror("mmap");
		close(fd);
		exit(1);
	}

	mmu_pagesize = get_proc_page_size((unsigned long)addr);

	close(fd);
	munmap(addr, alignment);

	if (mmu_pagesize != alignment) {
		printf("FAIL: MMUPageSize (%lu) != alignment (%lu)\n",
		       mmu_pagesize, alignment);
		exit(1);
	}

	printf("SUCCESS\n");
	exit(0);
}
