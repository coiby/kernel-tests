#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define MB	(1UL << 20)
#define GB	(1UL << 30)

int main(int argc, char **argv)
{
	char *p;
	int i;
	int N = atoi(argv[1]);
	if (N < 1) {
		fprintf(stderr,"Invalid argument\n");
		exit(1);	
	}

	posix_memalign((void **)&p, 2 * MB, N * GB);
	for (i = 0; i < 100; i++) {
		char *_p = p;
		while (_p < p+1*GB) {
			assert(*_p == *(_p+N/2*GB));
			_p += 4096;
			asm volatile ("": : :"memory");
		}
	}
	return 0;
}
