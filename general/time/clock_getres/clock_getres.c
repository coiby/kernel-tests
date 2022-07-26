#include <time.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>

#define diff(cur,prev) (cur.tv_sec < prev.tv_sec || (cur.tv_sec == prev.tv_sec && cur.tv_nsec < prev.tv_nsec))
#define COUNT 100000

int main(int argc, char *argv[])
{

	clockid_t clocks[] = {
		CLOCK_REALTIME,
		CLOCK_MONOTONIC,
		(clockid_t) -1,
	};

	char clk_name[][50] = {
		"CLOCK_REALTIME",
		"CLOCK_MONOTONIC",
	};

	struct timespec cur;
	struct timespec prev;
	struct timespec res;
	unsigned long count;
	int delay;
	int i,j;

	if(argc > 1)
		delay = atoi(argv[1]);
	else
		delay = 1;

	count = delay * COUNT;

	printf("Using delay=%u milliseconds between calls.\n", delay);
	printf("-----------------------------------------\n\n");

	for (i = 0; clocks[i] != (clockid_t) -1; i++) {
		printf("### Test Starting count = %d clockid = %s \n", i, clk_name[i]);

		if (clock_getres(clocks[i],&res)) {
			printf("Failed clock resolution read errno=%d [%s].\n",errno, strerror(errno));

			return 1;
		}
		printf("   %-25ssec = [%ld]   nsec = [%ld]",clk_name[i],res.tv_sec,res.tv_nsec);

		if (res.tv_nsec == 1)
			printf("   ====> High resolution mode\n");
		else
			printf("   ====> Low  resolution mode\n");

		if (clock_gettime(clocks[i], &cur) != 0) {
			printf("Failed the get the current time %s", clk_name[i]);

			return 1;
		}

		printf("   Initial time sec=%10lu nsec=%10lu\n",cur.tv_sec, cur.tv_nsec);

		j = 0;

		while(j < count){
			prev = cur;

			poll(0, 0, delay);

			if (clock_gettime(clocks[i], &cur) != 0) {
				printf("Failed the get the current time %s", clk_name[i]);

				return 1;
			}

			if (diff(cur,prev)) {
				printf("!!! FAILED:Time ran backward:\n\tcur:\t%lu%lu\n\tprev:\t%lu %lu\nInterval is >= %u milliseconds).\n",cur.tv_sec, cur.tv_nsec,prev.tv_sec, prev.tv_nsec,delay);
				
				return 1;
			}

			j++;
		}
	        printf("   --------------------------------------\n");
	}

	printf("\n==> Running done. PASS\n");

	return 0;
}
