/*
 * vma-split.c
 *
 * Copyright 2018, Red Hat, Inc.
 * Author: Jeff Moyer <jmoyer@redhat.com>
 * License: GLPv2+
 *
 * Description: This is a regression test.  mmap 2 pages of a device
 * dax instance read-only.  mprotect one page, setting it to
 * read-write.  This will split the vma up into two.  Then, after
 * mprotecting the page back to read-only, the two vmas should be
 * merged.  Check for this by walking /proc/pid/maps, and counting the
 * number of mappings we find.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/mman.h>
#include <libgen.h>
#include <fcntl.h>

#define LINE_MAX 4096

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
count_mappings(void *addr, unsigned long len)
{
	FILE *fp;
	int vmas = 0;
	int ret;
	unsigned long vma_start, vma_end;
	unsigned long dax_start = (unsigned long)addr,
		dax_end = dax_start + len - 1;
	char linebuf[LINE_MAX];

	fp = fopen("/proc/self/maps", "r");
	if (!fp) {
		perror("fopen /proc/self/maps");
		exit(1);
	}

	while (fgets(linebuf, LINE_MAX, fp) != NULL) {
		ret = sscanf(linebuf, "%lx-%lx", &vma_start, &vma_end);
		if (ret != 2) {
			fprintf(stderr, "fscanf returned %d\n", ret);
			fprintf(stderr, "%s\n", linebuf);
			exit(1);
		}

		/* check for overlap */
		if (dax_start <= vma_end && vma_start <= dax_end)
			vmas++;
	}

	if (ferror(fp)) {
		perror("fread ferror");
		exit(1);
	}

	fclose(fp);
	return vmas;
}

int
main(int argc, char **argv)
{
	int fd, ret;
	void *p;
	unsigned long align;

	if (argc != 3) {
		fprintf(stderr, "Usage: %s <dax device> <alignment>\n",
			basename(argv[0]));
		exit(1);
	}

	align = parse_size(argv[2]);

	fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		perror("open");
		exit(1);
	}

	p = mmap(NULL, 2UL * align, PROT_READ, MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		exit(1);
	}

	ret = mprotect(p, align, PROT_READ|PROT_WRITE);
	if (ret) {
		perror("mprotect PROT_READ|PROT_WRITE");
		exit(1);
	}

	ret = mprotect(p, align, PROT_READ);
	if (ret) {
		perror("mprotect PROT_READ");
		exit(1);
	}

	if (count_mappings(p, 2UL * align) > 1) {
		fprintf(stderr, "FAIL: VMAs were not merged.\n");
		exit(1);
	}

	printf("PASS\n");
	return 0;
}
