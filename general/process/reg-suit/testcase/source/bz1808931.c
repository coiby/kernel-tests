#include <signal.h>
#include <mqueue.h>
#include <unistd.h>
#include <sys/wait.h>
#include <assert.h>

static int notified;

static void sigh(int sig)
{
	notified = 1;
}

int main(void)
{
	signal(SIGIO, sigh);

	int fd = mq_open("/mq", O_RDWR|O_CREAT, 0666, NULL);
	assert(fd >= 0);

	struct sigevent se = {
		.sigev_notify   = SIGEV_SIGNAL,
		.sigev_signo    = SIGIO,
	};
	assert(mq_notify(fd, &se) == 0);

	if (!fork()) {
		assert(setuid(1) == 0);
		mq_send(fd, "",1,0);
		return 0;
	}

	wait(NULL);
	mq_unlink("/mq");
	assert(notified);
	return 0;
}
