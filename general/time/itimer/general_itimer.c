#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <sys/time.h>
#include <errno.h>
#include <time.h>
#include <stdlib.h>

volatile int value = 0;
volatile int count = 0;

struct itimer_sig
{
	int sig;
	int timerid;
};


void handler(int sig)
{
	//printf("process Caught signal %d\n", sig);
	
	if (++count == 100) {
		value = 1;
		count = 0;

		signal(sig,SIG_IGN);
	}
}

void configure_signal(int signum,struct sigaction *sa,void (*handler)(int sig))
{
	memset(sa, 0,sizeof(*sa));
	sa->sa_handler = handler;

        if (sigaction(signum, sa, NULL) == -1) {
                perror("sigaction");
                exit(1);
        }   

}

int analyse_result(char *s,struct timeval *start)
{
	unsigned long delta;
	struct timeval end;

        gettimeofday(&end, NULL);

        delta = (end.tv_sec * 1000000 + end.tv_usec) - (start->tv_sec * 1000000 + start->tv_usec);
 
	printf(">%s:\n",s);
        if ((unsigned long)delta/1000 > 1010) {
                printf("  Failed:\n\trunning for %lu ms\n\n",delta / 1000);

		return(1);

        }else{

                printf("  Pass:\n\trunning for %lu ms\n\n",delta / 1000);

		return(0);
        }   
}



int main(int argc, const char *argv[])
{
	int i = 0;
	int ret;
	struct sigaction sa;
	struct itimerval timer;

	struct timeval start,end;
	unsigned long delta;

	struct itimer_sig a[2] = {
		{ SIGPROF, ITIMER_PROF},
		{ SIGVTALRM, ITIMER_VIRTUAL},
	};

	for (i = 0; i < 2; i++) {

		configure_signal(a[i].sig,&sa,handler);	

		// timer expire after 10ms
		timer.it_value.tv_sec = 0;
		timer.it_value.tv_usec = 10000;

		// every 100ms expire 
		timer.it_interval.tv_sec = 0;
		timer.it_interval.tv_usec = 10000;
        
		setitimer(a[i].timerid, &timer, NULL);

		gettimeofday(&start, NULL);
        
		while(! value);

		value = 0;

		if (a[i].timerid == ITIMER_PROF)
			ret = analyse_result("ITIMER_PROF",&start);
		else
			ret = analyse_result("ITIMER_VIRTUAL",&start);
	}

	if (ret != 0)
		exit(1);
	else
		exit(0);
}
