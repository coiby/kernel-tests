#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#define THREAD_NUM (64L)
#define MEM_SIZE (1024*1024*1024*16L)
#define PER_TH_SIZE (MEM_SIZE/THREAD_NUM)

void *thread_func(void *data)
{
	char *addr = data;
	unsigned long size = PER_TH_SIZE, index = 0;
	int t;

	while (index < size) {
		t = *(addr + index);
		index += 4096;
	}
}

int main(int argc, char *argv[])
{
	int i;
	pthread_t threads[THREAD_NUM];
	pthread_attr_t attr;
	struct timeval start, stop, diff;
	char *mem;

	mem = mmap(NULL, MEM_SIZE, PROT_READ|PROT_WRITE,
		MAP_SHARED|MAP_ANON, 0, 0);
	if (!mem) {
		perror("mmap error");
		exit(1);
	}

	pthread_attr_init(&attr);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);
	gettimeofday(&start, NULL);
	for (i = 0; i < THREAD_NUM; i++)
		if (pthread_create(&threads[i], &attr, thread_func,
			mem + PER_TH_SIZE * i)) {
			perror("thread create error");
			exit(1);
		}

	for (i=0; i< THREAD_NUM; i++)
		pthread_join(threads[i], NULL);

	gettimeofday(&stop, NULL);
	timersub(&stop, &start, &diff);
	printf("Thread %ld Mem %dG time %lu.%03lusec\n",
		THREAD_NUM, MEM_SIZE/1024/1024/1024,
		diff.tv_sec, diff.tv_usec/1000);

	pthread_attr_destroy(&attr);
	return 0;
}
