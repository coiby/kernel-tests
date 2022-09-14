#include <unistd.h>
#include <time.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

int main(void)
{
	struct timespec ts = { 2, 150000 };
	int i;

	nanosleep(&ts, NULL);

	for (i = 0; i < 100000000; i++)
		asm volatile("" : : : "memory");

	ts.tv_sec = 100000;
	nanosleep(&ts, NULL);

	return 0;
}
