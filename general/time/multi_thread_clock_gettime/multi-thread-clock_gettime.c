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

struct timespec t1, t2;
FILE *f;
pthread_mutex_t work_mutex;

#define tv_lt(s,t) \
	(s.tv_sec < t.tv_sec || (s.tv_sec == t.tv_sec && s.tv_nsec < t.tv_nsec))

void print_error(struct timespec tv_start, struct timespec tv_end)
{
	long long time;
	struct timespec tv_diff;

	printf("start time = %10ld.%07ld \n", tv_start.tv_sec,
			tv_start.tv_nsec);
	printf("end   time = %10ld.%07ld \n", tv_end.tv_sec, tv_end.tv_nsec);

	if(tv_start.tv_nsec > tv_end.tv_nsec){
		tv_end.tv_sec--;
		tv_end.tv_nsec +=1000000L;
	}

	tv_diff.tv_sec = tv_end.tv_sec - tv_start.tv_sec;
	tv_diff.tv_nsec = tv_end.tv_nsec - tv_start.tv_nsec;
	time = (long long)tv_diff.tv_sec * 1000000000L +
		(long long)tv_diff.tv_nsec;
	printf("FAIL: time went backwards %lld nsec (%ld.%06ld )\n", time,
			tv_diff.tv_sec, tv_diff.tv_nsec);
}

int thread(void)
{
	int i;

	for(i=0;i<1000000000;i++) {
		if(pthread_mutex_lock(&work_mutex)==0) {
			//              clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
			clock_gettime(CLOCK_REALTIME, &t2);
			if(tv_lt(t2,t1)){
				print_error(t1,t2);
				//                        return(1);
			}
			t1=t2;
			//              fprintf(f, "%10ld.%07d\n", (long int)t1.tv_sec, (int)t1.tv_nsec);
			pthread_mutex_unlock(&work_mutex);
			//              usleep(1);
		}
	}
}

int main(int argc, char *argv[])
{
	int num;
	num=atoi(argv[1]);

	pthread_t tid[num];
	int i,ret;
	cpu_set_t mask[num];

	pthread_mutex_init(&work_mutex,NULL);

	for (i = 0; i < num; i++)
		CPU_ZERO(&mask[i]);

	for (i = 0; i < num; i++)
		CPU_SET(i, &mask[i]);

	clock_gettime(CLOCK_REALTIME, &t1);

	for (i = 0; i < num; i++) {
		ret=pthread_create(&tid[i],NULL,(void *) thread,NULL);
		if(ret!=0){
			printf ("Create pthread error!\n");
			return(1);
		}
		pthread_setaffinity_np(tid[i], sizeof(cpu_set_t), &mask[i]);
	}

	for (i = 0; i < num; i++) {
		pthread_join(tid[i],NULL);
	}

	return (0);
}
