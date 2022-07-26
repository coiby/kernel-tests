#include <stdio.h>
#include <time.h>
#include <sys/time.h>
#include <sys/timex.h>

int  main(void)
{
	struct timeval tv;
	struct timex tx;
	int ret;

	/* Get the current time */
	gettimeofday(&tv, NULL);

	/* Calculate the next leap second */
	tv.tv_sec += 86400 - tv.tv_sec % 86400;

	/* Set the time to be 10 seconds from that thatime */
	tv.tv_sec -= 10;
	settimeofday(&tv, NULL);

	/* Set the leap settimeofdaycond insert flag */
	tx.modes = ADJ_STATUS;
	tx.status = STA_PLL;
        adjtimex(&tx);

	tx.modes = ADJ_STATUS;
	tx.status = 0; 
        adjtimex(&tx);

	tx.modes = ADJ_STATUS;
	tx.status = STA_INS;
	
	ret = adjtimex(&tx);

	if (ret == -1){
		printf("error\n");
		return 2;
	}

	switch(ret) {
	case TIME_OK:
		printf("TIME_OK\n");
		break;
	case TIME_INS:
		printf("TIME_INS\n");
		break;
	case TIME_DEL:
		printf("TIME_DEL\n");
		break;
	case TIME_OOP:
		printf("TIME_OOP\n");
		break;
	case TIME_WAIT:
		printf("TIME_WAIT\n");
		break;
	case TIME_ERROR:
		printf("TIME_ERROR\n");
		break;
		
	}

	return 0;
}
