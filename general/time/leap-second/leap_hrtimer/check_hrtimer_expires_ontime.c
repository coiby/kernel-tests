#define _GNU_SOURCE
#include <stdio.h>
#include <stdbool.h>
#include <pthread.h>
#include <time.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/timex.h>
#include <sys/unistd.h>
#include <sched.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>


#define NSEC_PER_SEC 1000000000ULL
#define NS_PER_MS 1000000ULL
#define COUNT 1000

struct timespec timespec_add(struct timespec ts, unsigned long long ns)
{
        ts.tv_nsec += ns;
        while(ts.tv_nsec >= NSEC_PER_SEC) {
                ts.tv_nsec -= NSEC_PER_SEC;
                ts.tv_sec++;
        }
        return ts;
}


/* returns 1 if a <= b, 0 otherwise */
static inline int in_order(struct timespec a, struct timespec b)
{
        if(a.tv_sec < b.tv_sec)
                return 1;
        if(a.tv_sec > b.tv_sec)
                return 0;
        if(a.tv_nsec > b.tv_nsec)
                return 0;
        return 1;
}


void *test_hrtimer_failure(void *unused)
{
	int i = 0;
        struct timespec now, target;

	while(i < COUNT){
		clock_gettime(CLOCK_REALTIME, &now);
		//target = timespec_add(now, NSEC_PER_SEC/2);
		target = timespec_add(now, NS_PER_MS);
		clock_nanosleep(CLOCK_REALTIME, TIMER_ABSTIME, &target, NULL);
		clock_gettime(CLOCK_REALTIME, &now);

		if (!in_order(target, now)) {
			return (void *)(intptr_t)false;
		}

		++i;
	}

	return (void *)(intptr_t)true;
}


int main(int argc, const char *argv[])
{
        int i,ret;
	int cpu_count = sysconf(_SC_NPROCESSORS_CONF);

	pthread_t tid[cpu_count];
	cpu_set_t mask[cpu_count];

	printf("\t * Hrtimer Expire Testing start -> ");

        for (i = 0; i < cpu_count; i++)
		CPU_ZERO(&mask[i]);

	for (i = 0; i < cpu_count; i++)
		CPU_SET(i, &mask[i]);

        for (i = 0; i < cpu_count; i++) {

		ret = pthread_create(&tid[i], NULL, (void *)test_hrtimer_failure, NULL);
		if (ret != 0) {
			printf("pthread create thread %d error \n",i);

			return 2;
		}
		pthread_setaffinity_np(tid[i], sizeof(cpu_set_t), &mask[i]);
        }

	for (i = 0; i < cpu_count; i++) {
		void *retval = NULL;
		int ret = pthread_join(tid[i], &retval);
		if (ret) {
			printf("pthread_join[%d] failed: %s\n", i, strerror(ret));

			return 2;
		}

		if (!(bool)(intptr_t)retval) {
			printf("Fail:\n\t failure occurs on cpu %d\n", i);

			return 2;
		}
	}

	printf("PASS");

	return 0;
}
