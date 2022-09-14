#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>

#ifndef SHM_STAT_ANY
# define SHM_STAT_ANY 15
#endif

int main(int argc, char **argv)
{
	struct shmid_ds buf;
	int shmid;
	int ret = 0;
	int ret1 = 0;

	if (argc < 2) {
		printf("Usage: prog2 <shmid>\n\n");
		return 1;
	}
	shmid = atoi(argv[1]);

	ret = shmctl(shmid, SHM_STAT, &buf);
	if (ret < 0) {
		if (getuid() > 0 && errno == EACCES) {
			ret1 = 0;
			perror("expected fail: shmctl SHM_STAT");
		} else {
			ret1 = 1;
			perror("unexpected fail: shmctl SHM_STAT");
		}
	} else{
		if (getuid() != 0) {
			ret1 = 1;
			printf("unexpected success: shmctl(%d, SHM_STAT, ...)=%d\n", shmid, ret);
		} else  {
			ret1 = 0;
			printf("expected success: shmctl(%d, SHM_STAT, ...)=%d\n", shmid, ret);
		}
	}

	ret = shmctl(shmid, SHM_STAT_ANY, &buf);
	if (ret < 0) {
		perror("shmctl SHM_STAT_ANY");
		ret1 += 1;
	} else
		printf("shmctl(%d, SHM_STAT_ANY, ...)=%d\n", shmid, ret);

	return (ret1);
}

