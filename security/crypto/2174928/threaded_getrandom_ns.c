/* Author Dennis Li<denli@redhat.com> */
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/random.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>


unsigned char buf[8192];

typedef struct {
	int iterations;
	unsigned int flag;
} getrandom_struct;


void* getrandom_loop(void* args)
{
	getrandom_struct *actual_args = args;
	int i, iterations = actual_args->iterations;
	unsigned int flag = actual_args->flag;


	for (i = 0; i < iterations; i++) {
		if (getrandom(buf, sizeof buf, flag) <= 0)
			perror("getrandom error");
	}
	free(actual_args);
}

/*
 * Measure the time (machine cycles) it takes to call getrandom when getrandom(GRND_RANDOM) is runing at the same time
 */
int main(int argc, char **argv)
{

	pthread_t thread1, thread2;
	int iterations = atoi(argv[1]);

	getrandom_struct *args_GRND = malloc(sizeof *args_GRND);
	args_GRND->iterations = iterations;
	args_GRND->flag = GRND_RANDOM;

	getrandom_struct *args_0 = malloc(sizeof *args_0);
	args_0->iterations = iterations;
	args_0->flag = 0;


	pthread_create(&thread1, NULL, getrandom_loop, args_GRND);


	struct timespec start;
	clock_gettime (CLOCK_PROCESS_CPUTIME_ID, &start);
	
	pthread_create(&thread2, NULL, getrandom_loop, args_0);
	// only wait for getrandom(no flag) thread to finish
	pthread_join(thread2, NULL); 


	struct timespec end;
	clock_gettime (CLOCK_PROCESS_CPUTIME_ID, &end);
	unsigned int elapsed_ms = (end.tv_sec - start.tv_sec) * 1000 + (end.tv_nsec - start.tv_nsec) / (1000 * 1000);
	double ftime = ((double) elapsed_ms * 1000/ iterations);
	printf ("Average getrandom function time %.0f ns\n", ftime);
	fprintf(stderr, "%.0f,", ftime);
}