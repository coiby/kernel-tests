/* Author Dennis Li<denli@redhat.com> */
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/random.h>
#include <unistd.h>
#include <pthread.h>

static __inline__ u_int64_t start_clock();
static __inline__ u_int64_t stop_clock();
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

	u_int64_t start_rdtsc = start_clock();
	pthread_create(&thread2, NULL, getrandom_loop, args_0);

	// only wait for getrandom(no flag) thread to finish
	pthread_join(thread2, NULL); 
	u_int64_t stop_rdtsc = stop_clock();
	u_int64_t diff = stop_rdtsc-start_rdtsc;


	printf("TSC for %d getrandom calls: %ldK cycles.  Avg cycles per call: %ld\n",
	       iterations,
	       diff/1000,
	       diff/iterations);
	fprintf(stderr, "%ld,", diff/iterations);
}

static __inline__ u_int64_t start_clock() {
	// See: Intel Doc #324264, "How to Benchmark Code Execution Times on Intel...",
	u_int32_t hi, lo;
	__asm__ __volatile__ (
		"CPUID\n\t"
		"RDTSC\n\t"
		"mov %%edx, %0\n\t"
		"mov %%eax, %1\n\t": "=r" (hi), "=r" (lo)::
		"%rax", "%rbx", "%rcx", "%rdx");
	return ( (u_int64_t)lo) | ( ((u_int64_t)hi) << 32);
}

static __inline__ u_int64_t stop_clock() {
	// See: Intel Doc #324264, "How to Benchmark Code Execution Times on Intel...",
	u_int32_t hi, lo;
	__asm__ __volatile__(
		"RDTSCP\n\t"
		"mov %%edx, %0\n\t"
		"mov %%eax, %1\n\t"
		"CPUID\n\t": "=r" (hi), "=r" (lo)::
		"%rax", "%rbx", "%rcx", "%rdx");
	return ( (u_int64_t)lo) | ( ((u_int64_t)hi) << 32);
}