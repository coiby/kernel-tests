#include <unistd.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <time.h>
#include <errno.h>

#include <cstdlib>
#include <iostream>
using namespace std;

int main(int argc, char* argv[])
{
	if (argc < 2)
	{
		cerr << "sem key required" << endl;
		return 1;
	}
	int key = atoi(argv[1]);
	int semid = semget(key, 1, IPC_CREAT | IPC_EXCL | 0777);
	if (semid == -1)
	{
		cerr << "error, failed to create semaphore key=" << key << endl;
		return 1;
	}

	cout << "semaphore created, semid = " << semid << endl;
	sleep(10);

	while (true)
	{
		struct sembuf sops;
		sops.sem_num = 0;
		sops.sem_op = 0;    
		sops.sem_flg = IPC_NOWAIT;

		int rc;
		do
		{
			rc = semop(semid, &sops, 1);
		} while ((rc == -1) && (errno == EINTR));

		if (rc == -1)
		{
			cerr << "error, semop failed, semid = " << semid << ", errno = " << errno << endl;
			return 1;
		}
		sleep(10);
	}
}

