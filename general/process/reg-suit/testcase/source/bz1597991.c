#define _GNU_SOURCE
#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <pthread.h>

#define CLONE_NEWUSER       0x10000000
void sig_func(int s, siginfo_t *si, void *c)
{
	return;
}

void *thr(void* arg)
{
    char buf[1024];
    long fds = (long)arg;
    int ret, s = 0;
    while (1) {
        ret = read(fds, buf, 2);
        lseek(fds, 0, SEEK_SET);
	if (!s) {
                pid_t parent = getppid();
		sigval_t sv = {.sival_int = parent, };
		sigqueue(getppid(), SIGUSR1, sv);
		s=1;
	}
    }
}

int main(int argc, char* argv[]) {
	int i = 0;
	char *namespaces[] = { "user", "uts", "net", "pid", "mnt" };
	int ret = 0;
	pthread_t thread;

	if (geteuid()) {
		fprintf(stderr, "%s\n", "abort: you want to run this as root");
		exit(1);
	}

	struct sigaction act = {};
	act.sa_sigaction = sig_func;
	act.sa_flags = SA_SIGINFO;
	if (sigaction(SIGUSR1, &act, NULL) < 0) { 
		perror("sigaction");
		exit(1);
	}

	int stub = fork();
	if (stub == 0) {
		char nspath[1024];
                pid_t parent = getppid();
		sprintf(nspath, "/proc/%d/coredump_filter", parent);
		long fds = open(nspath, O_RDONLY);
		if (fds < 0) {
			perror("open");
			return 1;
		}
		pthread_create(&thread, NULL, thr, (void*)fds);
		pthread_create(&thread, NULL, thr, (void*)fds);
		pthread_create(&thread, NULL, thr, (void*)fds);
		pthread_create(&thread, NULL, thr, (void*)fds);
		sleep(500);
	}
        
        pause();
        
		int fail = 0;
        while (1) {
		if (unshare(CLONE_NEWUSER) < 0) {
			fail++;
			if (fail == 1)
				fprintf(stderr, "unsahre() %s namespace failed: %s\n",
					namespaces[i], strerror(errno));
			continue;
		}
		fprintf(stdout, "unshare on %s namespace succeeded after %d failures\n", namespaces[i], fail);
		break;
	}
	return !!fail;
}
