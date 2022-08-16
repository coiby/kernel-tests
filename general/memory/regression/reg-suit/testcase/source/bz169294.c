#include <stdio.h>
#include <sys/types.h>
#include <fcntl.h>
#include <stdlib.h>

#define FDS		2045
#define DIR		"/mnt/testarea"
#define FNAME_LEN	128
#define FNAME(buf, dir, fname)	sprintf(buf, "%s/%d", dir, fname)

int main(int argc, char *argv[])
{
	int i, fds = FDS;
	char fname[FNAME_LEN];
	unsigned long addr;

	addr = strtoul(argv[1], NULL, 0);
	if (argc == 3)
		fds = atoi(argv[2]);

	for (i = 0, FNAME(fname, DIR, i); i < fds; i++, FNAME(fname, DIR, i)) {
		if (open(fname, O_CREAT|O_RDWR, 0644) < 0) {
			printf("i=%d\n", i);
			perror("open");
			exit(1);
		}
	}

	FNAME(fname, DIR, i);
	asm volatile ("lfetch [%0]" : : "r"(addr));
	open(fname, O_CREAT|O_RDWR, 0644);

	return 0;
}
