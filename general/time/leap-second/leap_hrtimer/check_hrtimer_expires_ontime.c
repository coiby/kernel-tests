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
#include <unistd.h>
#include <stdlib.h>


#define NSEC_PER_SEC 1000000000ULL
#define COUNT 1000

int *p; 

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


void test_hrtimer_failure(void * arg)
{       
	int i = 0;
	int cpu_number = *((int *)arg);

        struct timespec now, target;

	while(i < COUNT){
		clock_gettime(CLOCK_REALTIME, &now);
		//target = timespec_add(now, NSEC_PER_SEC/2);
		target = timespec_add(now, NSEC_PER_SEC/1000);
		clock_nanosleep(CLOCK_REALTIME, TIMER_ABSTIME, &target, NULL);
		clock_gettime(CLOCK_REALTIME, &now);

		if (!in_order(target, now)) {
			printf("Note: hrtimer early expiration failure observed in cpu %d \n",cpu_number);

			*(p + cpu_number) = 1;

			return;
		}

		++i;
	}

}


int main(int argc, const char *argv[])
{
        int i,ret;
	int cpu_count = sysconf(_SC_NPROCESSORS_CONF);
	int parameter[cpu_count];

	pthread_t tid[cpu_count];
	cpu_set_t mask[cpu_count];

	printf("\t * Hrtimer Expire Testing start -> ");

        p = (int *)malloc(sizeof(int) * cpu_count);

	for (i = 0; i < cpu_count; i++) {
		*(p + i) = 0;
	}

        for (i = 0; i < cpu_count; i++)
		CPU_ZERO(&mask[i]);

	for (i = 0; i < cpu_count; i++)
		CPU_SET(i, &mask[i]);

        for (i = 0; i < cpu_count; i++) {
                parameter[i] = i;

        	ret = pthread_create(&tid[i],NULL,(void *)test_hrtimer_failure,(void *)(parameter + i));
		if (ret != 0) {
			printf("pthread create thread %d error \n",i);

			return 2;
		}
		pthread_setaffinity_np(tid[i], sizeof(cpu_set_t), &mask[i]);
        }

	for (i = 0; i < cpu_count; i++) {
		pthread_join(tid[i],NULL);
	}

	for (i = 0; i < cpu_count; i++) {
		if (*(p + i)) {
			printf("Fail:\n\t failture occurs on cpu %d \n",i);

			return 2;
		}
		
	}
	
 
	printf("PASS");

	return 0;
}
