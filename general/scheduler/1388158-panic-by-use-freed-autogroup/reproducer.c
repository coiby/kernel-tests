#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <assert.h>


int main(void)
{
        int sctl = open("/proc/sys/kernel/sched_autogroup_enabled", O_WRONLY);
        int loop = 60;
        assert(sctl > 0);
        if (fork()) {
                wait(NULL); // destroy the child's ag/tg
                pause();
        }

        assert(pwrite(sctl, "1\n", 2, 0) == 2);
        assert(setsid() > 0);
        if (fork())
                pause();

        kill(getppid(), SIGKILL);
        sleep(1);

        // The child has gone, the grandchild runs with kref == 1
        assert(pwrite(sctl, "0\n", 2, 0) == 2);
        assert(setsid() > 0);

        // runs with the freed ag/tg
        while (loop-- > 0) {
                sleep(1);
        }

        return 0;
}

