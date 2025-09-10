#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>

#define N_SYSCALLS 600

int main() {
    int i;
    long ret;

    for (i = 0; i < N_SYSCALLS; i++) {
        if (i == 58) { printf ("%d, implemented\n",  i); continue; } // vhangup
        if (i == 93) { printf ("%d, implemented\n",  i); continue; } // exit
        if (i == 94) { printf ("%d, implemented\n",  i); continue; } // exit_group
        if (i == 139) { printf ("%d, implemented\n", i); continue; } // sigreturn

        ret = syscall(i);
        if (ret == 0) {
            printf ("%d, implemented\n",  i);
        } else {
            int sysret = errno;

            if (sysret == ENOSYS)
                printf ("%d, not implemented\n", i);
            else if (sysret == EPERM)
                printf ("%d, implemented, no permission\n", i);
            else
                printf ("%d, implemented\n", i);
        }
    }

    return 0;
}
