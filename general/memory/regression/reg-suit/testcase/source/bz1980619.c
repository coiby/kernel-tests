/*
 * shm-test.c - simple reproducer for RHBZ#1980619
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
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdbool.h>
#include <limits.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/times.h>
#include <sys/time.h>
#include <sys/ipc.h>
#include <sys/shm.h>

unsigned long usec_diff(struct timeval *a, struct timeval *b)
{
	unsigned long usec;

	usec = (b->tv_sec - a->tv_sec) * 1000000;
	usec += b->tv_usec - a->tv_usec;
	return usec;
}

int init_ids(int *ids, int cnt)
{
	int i, fails = 0;

	for (i = 0; i < cnt; i++)
		ids[i] = INT_MIN;

	for (i = 0; i < cnt; i++) {
		ids[i] = shmget(IPC_PRIVATE, getpagesize(), IPC_CREAT | IPC_EXCL);

		if (ids[i] == -1) {
			if (!fails)
				perror("shmget");
			fails += 1;
		}
	}

	return fails;
}

void delete_ids(int *ids, int cnt)
{
	for (int i = 0; i < cnt; i++) {
		if (ids[i] >= 0) {
			shmctl(ids[i], IPC_RMID, NULL);
			ids[i] = INT_MIN;
		}
	}
}

int main(int argc, char *argv[])
{
	struct timeval start, end;
	int count = 32768;
	int bytes = getpagesize();
	int i, r, fd, fails;
	int *ipcids;
	char *buffer;

	if (argc > 1)
		count = atoi(argv[1]);

	if ((buffer = calloc(bytes, sizeof *buffer)) == NULL)
		return -ENOMEM;

	if ((ipcids = malloc(count * sizeof *ipcids)) == NULL) {
		free(buffer);
		return -ENOMEM;
	}

	fails = init_ids(ipcids, count);

	if ((fd = open("/proc/sysvipc/shm", O_RDONLY)) < 0) {
		perror("open");
		delete_ids(ipcids, count);
		free(ipcids);
		free(buffer);
		return EXIT_FAILURE;
	}

	gettimeofday(&start, NULL);
	while ((r = read(fd, buffer, bytes - 1)) > 0) {
		if (r == -1 && errno != EINTR)
			break;
	}
	gettimeofday(&end, NULL);

	printf("%6lu msecs to read %6d segs from /proc/sysvipc/shm\n",
		usec_diff(&start, &end)/1000,
		(count - fails));

	delete_ids(ipcids, count);
	close(fd);
	free(ipcids);
	free(buffer);

	return EXIT_SUCCESS;
}
