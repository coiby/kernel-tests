#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>


// not milisec but increased by 10 to allow for more time
// on low powered cpu's.
#define MSECREQ 10000

void event_handler (int signum)
{
     //printf("expire time");
}

int main (int argc, char **argv)
{
    struct sigaction sa;
    struct itimerval timer;

    memset (&sa, 0, sizeof (sa));
    sa.sa_handler = &event_handler;
    sigaction (SIGALRM, &sa, NULL);

    timer.it_value.tv_sec = 0;
    timer.it_value.tv_usec = MSECREQ;
    timer.it_interval.tv_sec = 0;
    timer.it_interval.tv_usec = MSECREQ;

    setitimer (ITIMER_REAL, &timer, NULL);

    while (1) {
        pause();
    }
}
