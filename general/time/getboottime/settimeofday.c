#include <stdio.h>
#include <errno.h>
#include <linux/time.h>

int main(int argc, const char *argv[])
{
	struct timeval tv;

	if (gettimeofday(&tv, NULL)) {
		perror("gettimeofday");
		
		return 1;
	}

	++tv.tv_sec;
	if (settimeofday(&tv,NULL)) {
		perror("settimeofday");
		
		return 1;
	}

	return 0;
}
