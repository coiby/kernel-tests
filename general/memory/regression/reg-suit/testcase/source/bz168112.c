/* threadexec.c: description
 *
 * Copyright (C) 2005 Red Hat, Inc. All Rights Reserved.
 * Written by David Howells (dhowells@redhat.com)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sched.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <linux/unistd.h>
#include <errno.h>
#include <pthread.h>

char *prog;
int iteration;

void *sleeper(void *x)
{
//	pause();
	for (;;)
		sleep(1);
}

void *executor(void *x)
{
	char iter[30];

	sprintf(iter, "%d", iteration + 1);

	execlp(prog, prog, iter, NULL);

	perror("execlp");
	exit(1);
}

int main(int argc, char *argv[])
{
	int loop;

	prog = argv[0];

	if (argc == 1)
		iteration = 1;
	else
		iteration = atoi(argv[1]);

	if (iteration >= 1000)
		exit(0);

	/* allocate a bunch of threads that just sleep over and over again */
	for (loop = 0; loop < 8; loop++) {
		pthread_t thread;
		if (pthread_create(&thread, NULL, sleeper, NULL) < 0) {
			perror("pthread_create");
			exit(1);
		}
	}

	/* the main thread execs on odd iterations */
	if (iteration & 1)
		executor(NULL);

	/* the last subsidiary thread execs on even iterations */
	pthread_t thread;
	if (pthread_create(&thread, NULL, executor, NULL) < 0) {
		perror("pthread_create");
		exit(1);
	}

	sleeper(NULL);
	exit(2);
}


