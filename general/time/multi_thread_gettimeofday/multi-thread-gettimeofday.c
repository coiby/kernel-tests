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
FILE *f;
pthread_mutex_t work_mutex; 

#define tv_lt(s,t) \
 (s.tv_sec < t.tv_sec || (s.tv_sec == t.tv_sec && s.tv_usec < t.tv_usec))

void print_error(struct timeval tv_start, struct timeval tv_end)
{
        long long time;
        struct timeval tv_diff;

        printf("start time = %10ld.%07ld \n", tv_start.tv_sec,
               tv_start.tv_usec);
        printf("end time = %10ld.%07ld \n", tv_end.tv_sec, tv_end.tv_usec);

        if(tv_start.tv_usec > tv_end.tv_usec){
                        tv_end.tv_sec--;
                        tv_end.tv_usec +=1000000L;
        }

        tv_diff.tv_sec = tv_end.tv_sec - tv_start.tv_sec;
        tv_diff.tv_usec = tv_end.tv_usec - tv_start.tv_usec;
        time = (long long)tv_diff.tv_sec * 1000000000L +
               (long long)tv_diff.tv_usec * 1000L;
        printf("Failed: time went backwards %lld nsec (%ld.%06ld )\n", time,
               tv_diff.tv_sec, tv_diff.tv_usec);
}

int thread(void)
{
	int i;

	for(i=0;i<1000000;i++) {
		if(pthread_mutex_lock(&work_mutex)==0) {
			gettimeofday(&t2,NULL);
        		if(tv_lt(t2,t1)){
                       		print_error(t1,t2);
                        	return(1);
                	}
			t1=t2;		
//			fprintf(f, "%10ld.%07d\n", (long int)t1.tv_sec, (int)t1.tv_usec);
			pthread_mutex_unlock(&work_mutex);
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

	gettimeofday(&t1,NULL);
	printf("main->gettimeofday: %10d.%07d\n", (int)t1.tv_sec, (int)t1.tv_usec);

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
