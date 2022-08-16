#include <stdlib.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/sem.h>

int main(int argc, char *argv[])
{
	int ret, sem_id, snum, num_cnt;
	unsigned short *array;

	snum = argc > 1 ? atoi(argv[1]) : 0;

	if(!snum) {
		printf("Please pass number as parameter.\n");
		return(0);
	}

	array = malloc(sizeof(unsigned short) * snum);
	if(!array) {
		printf("malloc failed.\n");
		return(1);
	}

	sem_id = semget(IPC_PRIVATE, snum, IPC_CREAT | 0666);
	if(-1 == sem_id) {
		printf("semget failed.\n");
		free(array);
		return(2);
	}

	for(num_cnt = 0; num_cnt < snum; num_cnt++) {
	        array[num_cnt] = 1;

	}

	ret = semctl(sem_id, 0, SETALL, array);
	if(-1 == ret) {
		printf("semctl(SETALL) failed.\n");
		semctl(sem_id, 0, IPC_RMID);
		free(array);
		return(3);
	}

	printf("snum=%d semid=%u \n", snum, sem_id);

	semctl(sem_id, 0, IPC_RMID);
	free(array);

	return(0);
}
