#include <stdio.h>
#include <stdlib.h>
#include <sys/shm.h>

int main(int argc, char **argv) {
	size_t sz;
	long long sztmp;
	int shmid;
	key_t key;
	struct shmid_ds buf;

	if(argc == 1)
		sztmp = 0x80000000;
	else
		sztmp = atoll(argv[1]);

	sz = (unsigned) sztmp;

	key = (key_t)7823;
	shmid = shmget(key, sz, IPC_CREAT | IPC_EXCL | 0777);
	if(shmid == -1){
		fprintf(stderr,
			"Can not allocate a segment of size: %lu 0x%lx\n"
			"Please check /proc/sys/kernel/shmmax\n",
			(long)sz, (long)sz);
		perror("shmget");
		exit(1);
	}

	printf("Segment of size %lu (0x%lx) successfully allocated. shmid: %i\n", (long)sz, (long)sz, shmid);

	if( shmctl(shmid, IPC_RMID, &buf) ){
		perror("shmctl");
		exit(1);
	}

	return 0;
}
