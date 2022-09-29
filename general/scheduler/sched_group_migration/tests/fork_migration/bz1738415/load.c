#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>
#include <sys/wait.h>

void do_sleep()
{
	int j = 0;
	struct timespec t = {.tv_sec = 0, .tv_nsec = 1000000 };
	nanosleep(&t, 0);
	for (j=0; j< 1000000; j++);
}

int main()
{
	int i, j;
	int pid;
	int ret;
	printf("pid=%d\n", getpid());
	for (;;) {
		for (i=0; i < 1000; i++) {
			pid = fork();
			if (pid == 0) {
				do_sleep();
				return 0;
			}
		}
		j = 0;
		while (wait(NULL) > 0) {
			j++;
		}
	}
}

