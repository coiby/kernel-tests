#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>


int main(int argc, char **argv)
{
	int iofd[2];
	int i;
	int m = argc > 1?atoi(argv[1]): 1;
	for (i=1; i<m+1; i++) {
		printf("pipe %d\n", i);
		if (pipe(iofd)) {
			perror("pipe");
			return 1;
		} else {
			printf("pair: %d %d\n", iofd[0], iofd[1]);
		}
	}


	int pid = -1;
	if ((pid=fork()==0)) {
		int ret = fcntl(iofd[1], F_GETPIPE_SZ);

		printf("pipesize=%d\n", ret);

		printf("pipe size setting to=%d", 4*getpagesize());
		ret = fcntl(iofd[1], F_SETPIPE_SZ, 4*getpagesize());
		if (ret < 0) {
			puts(" failed");
			perror("F_SETPIPE_SZ");
		} else {
			puts(" passed");
		}

		ret = fcntl(iofd[1], F_GETPIPE_SZ);
		printf("pipesize=%d\n", ret);
	}
	return 0;
}
