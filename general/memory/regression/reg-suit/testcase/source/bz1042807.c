#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/msg.h>

struct msgbuf
{
	long mtype;     /* message type, must be > 0 */
	char mtext[16]; /* message data */
};


static int msr(int msqid)
{
	struct msgbuf msbs;
	struct msgbuf msbr;
	ssize_t sret;
	long   mtype = 121;

	memset(&msbs, 0, sizeof(msbs));
	msbs.mtype = mtype;

	if (msgsnd(msqid, &msbs, sizeof(msbs.mtext), IPC_NOWAIT))
	{
		perror("msgsnd");
		return -1;
	}

	sleep(5);

	sret = msgrcv(msqid, &msbr, sizeof(msbr.mtext), -mtype, IPC_NOWAIT | MSG_NOERROR);

	if (sret < 0)
	{
		perror("msgrcv");
		return -1;
	}

	if (msbr.mtype != mtype)
	{
		printf("found mtype %ld, expected %ld\n", msbr.mtype, mtype);
		return -1;
	}

	if ((size_t)sret != sizeof(msbs.mtext))
	{
		printf("received %lu, expected %lu\n",
				(unsigned long)sret, (unsigned long)sizeof(msbs.mtext));
		return -1;
	}

	return 0;
}

int main(void)
{
	int ret;
	int msqid = msgget(IPC_PRIVATE, IPC_CREAT | IPC_EXCL | 0666);

	if (msqid < 0)
	{
		perror("msgget");
		return -1;
	}

	ret = msr(msqid);

	if (msgctl(msqid, IPC_RMID, 0))
	{
		perror("msgctl");
		return -1;
	}

	return ret;
}
