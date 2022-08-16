/*
 * Reproducer of bz1309898
 *
 * Creates a tree of process that all have a bunch of zeroed pages
 * meant to be mergeded by ksm, wait a bit to give ksm a chance to
 * merge the pages and then exit.
 *
 * You should have ksm service running (and probably ksmtuned stopped
 * so it would not interfere).
 */

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/wait.h>

#define MAXDEPTH 4 /* Depth of process tree */
#define ARITY    2 /* Number of children per process */

#define BUFSZ (4096 * 1024)

#ifdef DEBUG
#define pr_dbg(fmt, ...) printf(fmt, ##__VA_ARGS__)
#else
#define pr_dbg(fmt, ...) {};
#endif

/* No integer power function in standard libc? */
int ipow(int base, unsigned int exp) {
    int i, result = 1;

    for (i = 0; i < exp; i++)
        result *= base;

    return result;
}

/* Geometric series */
int nr_chlidren() {
	return (ipow(ARITY, MAXDEPTH + 1) - 1) / (ARITY - 1) - 1;
}

int main(int argc, char *argv[])
{
	int i, ret, depth = 0;
	pid_t pids[ARITY];
	char *buf = mmap(NULL, BUFSZ, PROT_READ | PROT_WRITE,
			 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	
restart:
	for (i = 0; i < ARITY; i++) {
		pids[i] = fork();
		if (pids[i] == -1) {
			/* error */
			perror("fork");
			return 1;
		}
		if (!pids[i]) {
			depth++;
			pr_dbg("pid: %i - depth: %i - pos:%i\n",
			       getpid(), depth, i);
			if (depth >= MAXDEPTH)
				break;
			goto restart;
		}
	}

	ret = madvise(buf, BUFSZ, MADV_MERGEABLE);
	if (ret)
		perror("madvise");

	memset(buf, 0, BUFSZ);

	/* Wait on the elder */
	if (depth)
		raise(SIGSTOP);
	else
		/* Give ksm a chance */
		sleep(1);

	/* Wake up our children */
	if (depth < MAXDEPTH)
		for (i = 0; i < ARITY; i++) {
			kill(pids[i], SIGCONT);
			wait(NULL);
		}

	if (!depth)
		goto restart;

	return 0;
}
