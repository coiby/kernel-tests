#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <time.h>

#include <stdlib.h>
#include <iostream>
using namespace std;

int main(int argc, char* argv[])
{
	if (argc < 2)
	{
		cerr << "semid required" << endl;
		return 1;
	}
	int semId = atoi(argv[1]);

	struct semid_ds semds;
	union semun 
	{
		int val;
		struct semid_ds *buf;
		unsigned short *array;
	} arg;
	arg.buf = &semds;

	/* get the time of the last semaphore operation */
	if (semctl(semId, 0, IPC_STAT, arg) == -1)
	{
		cerr << "semctl fail" << endl;
		return 1;
	}

	cout << (time(0) - semds.sem_otime) << endl;
}
