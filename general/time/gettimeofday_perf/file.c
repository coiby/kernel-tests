#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <time.h>

int master = 0; /* are we the parent process */
pid_t children[1024]; /* pids of child processes */
int count; /* process count */
unsigned long iter; /* number of calls made. */
int k; /* global variable into which the tick() results are added. To prevent the compiler optimising out the calls to tick(). */

void wake_me(int seconds, void (*func)())
{
    /* set up the signal handler */
    signal(SIGALRM, func);
    /* get the clock running */
    alarm(seconds);
}

/* this is our tick function that got significantly slower */
unsigned int tick(void)
{
    unsigned int uCurTick;
    struct timeval now;

    gettimeofday(&now, 0);
    uCurTick = (unsigned int)((now.tv_sec*1000) + now.tv_usec/1000);

    return(uCurTick);
}

/* printout the results. sleeps used to fix display issues in the shell. */
/* the sleeps occurs after counts have been gather, wont affect performance */
void report()
{
    int status,i;
    printf("%lu+", iter);
    fflush(stdout);

    if (master)
    {
        for(i = 0; (i < (count - 1)); i++)
        {
            waitpid(children[i], &status, WEXITED);
        }
        sleep(2);
        printf("\n");
        sleep(2);
        exit(0);
    }
    else
    {
        sleep(5);
        exit(0);
    }
}

int main(int argc, char* argv[])
{
    int i,depth,duration;
    unsigned int time0 = time(0);

    if (argc < 3)
    {
        printf("Usage: %s duration count \n", argv[0]);
        exit(0);
    }

    duration = atoi(argv[1]);
    count = atoi(argv[2]);
    depth = 8;
    iter = 0;

    for(i = 0; (i < (count - 1)) && (children[i] = fork()); i++);

    if (i == (count - 1))
    {
        master = 1;
    }

    /* synchronise the start time of all processes */
    /* forking might take time */
    while(((unsigned int)(time(0) - time0)) < 5)
    {
        sleep(0);
    }

    /* the test starts here */
    wake_me(duration, report);

    /* tight loop were we simply call tick() over and over */
    k=0;
    do
    {
        k += tick();
        iter++;
    }
    while(1);

    return(0);
}
