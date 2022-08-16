/*
 * repro.c - simple reproducer for RHBZ#1837531
 *
 * Copyright (c) 2021 Rafael Aquini <aquini@redhat.com>
 *
 * Permission to use, copy, modify, and distribute this software
 * for any purpose with or without fee is hereby granted.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

#ifndef NLOOPS
#define NLOOPS 1000
#endif

#ifndef EFIVARSDIR
#define EFIVARSDIR "/tmp/efivars"
#endif

#ifndef TEMPFILE
#define TEMPFILE "/tmp/tempfile"
#endif

#ifndef MAP_SIZE
#define MAP_SIZE 8192
#endif

enum work {
	READER,
	WRITER,
	WORKERS
};

struct worker {
	char *name;
	int loops;
	void *data;
	int (*func)(struct worker *);
};

static void die(const char *msg)
{
        perror(msg);
        exit(errno ? errno : EXIT_FAILURE);
}

static void print_header(struct worker *w)
{
	printf("%s [pid:%ld]: working on %s (%d loops)\n",
		w->name, (long)getpid(), (char *)w->data, w->loops);
}

int reader(struct worker *w)
{
	int i;
	DIR *dir;
	struct dirent *entry;
	char *dpath = (char *)w->data;

	print_header(w);

	for (i = 0; i < w->loops; i++) {
		if ((dir = opendir(dpath)) == NULL)
			die("opendir");

		while ((entry = readdir(dir)) != NULL) {
			struct stat s;
			char *path = NULL;

			asprintf(&path, "%s/%s", dpath, entry->d_name);
			if (lstat(path, &s) < 0)
				goto next_entry;

			if ((s.st_mode & S_IFMT) == S_IFREG) {
				char buf[1024];
				int fd, r;

				if ((fd = open(path, O_RDONLY)) < 0)
					goto next_entry;

				while ((r = read(fd, buf, sizeof(buf))) > 0) {
					if (r == -1 && errno != EINTR)
						break;
				}

				close(fd);
			}
next_entry:
			free(path);
		}

		closedir(dir);
	}

	return EXIT_SUCCESS;
}

int writer(struct worker *w)
{
	char *addr, *fpath = (char *)w->data;
	int off, fd, i;

	print_header(w);

	if ((fd = open(fpath, O_RDWR)) < 0)
		die("open");

	addr = mmap(NULL, MAP_SIZE, PROT_WRITE, MAP_SHARED, fd, 0);
	if (addr == MAP_FAILED)
		die("mmap");

	for (i = 0; i < w->loops; i++) {
		for (off = 0; off < MAP_SIZE; off++)
			addr[off] = off;
		sync();
	}

	close(fd);

	return EXIT_SUCCESS;
}

int main(int argc, char *argv[])
{
	pid_t pid;
	char *efivarfs, *tempfile;
	int i, loops, ret, status;
	struct worker child[WORKERS];

	loops = (argc > 1) ? atoi(argv[1]) : NLOOPS;
	tempfile = (argc > 2) ? argv[2] : TEMPFILE;
	efivarfs = (argc > 3) ? argv[3] : EFIVARSDIR;

	child[READER].name = "EFIvars reader";
	child[READER].func = reader;
	child[READER].data = efivarfs;
	child[READER].loops = loops * 10;

	child[WRITER].name = "mapped file writer";
	child[WRITER].func = writer;
	child[WRITER].data = tempfile;
	child[WRITER].loops = loops;

	for (i = 0; i < WORKERS; i++) {
		pid = fork();
		switch (pid) {
		case -1:
			die("fork");
			break;
		case 0:         /* child of a sucessful fork() */
			ret = child[i].func(&child[i]);
			exit(ret);
			break;
		}
	}

	for (;;) {
		if ((pid = wait(&status)) == -1) {
			switch (errno) {
			case ECHILD:
				goto out;
			default:
				die("wait");
			}
		}

		printf("PID=%ld  wait() returned child PID %ld\n",
		        (long) getpid(), (long) pid);
	}
out:
	return EXIT_SUCCESS;
}
