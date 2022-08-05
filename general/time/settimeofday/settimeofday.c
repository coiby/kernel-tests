#define _GNU_SOURCE
#include <stdio.h>
#include <pthread.h>
#include <time.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/timex.h>
#include <sys/unistd.h>
#include <sched.h>
#include <sys/types.h>

struct timeval t1, t2;

int main(void)
{

	int i=0;

	gettimeofday(&t1,NULL);
	printf("time = %10ld.%07ld \n", t1.tv_sec, t1.tv_usec);

	for (i=1; i<1000; i++)
	{

		t1.tv_sec=t1.tv_sec + 1;

		settimeofday(&t1,NULL);
		sleep(0.5);
	}

	gettimeofday(&t1,NULL);

	printf("time = %10ld.%07ld \n", t1.tv_sec, t1.tv_usec);
	printf("PASS\n");
	return (0);
}
