/*
 *
 * (from root console): trace-cmd record  -e syscalls:sys_enter_write
 * (from user): ./ftrace
 *
 */

#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <signal.h>
#include <sys/prctl.h>
#include <unistd.h>

int main(void) {
  pid_t pid = fork();
  if (pid == 0) {
    prctl(PR_SET_PDEATHSIG, SIGKILL);
    pid_t ppid = getppid();
    for (;;) {
      kill(ppid, SIGCONT);
    }
  }

  unsigned int i = 0;
  for(;;) {
    syscall(0x10000000, 0, 0, 0, 0, 0, 0);
  }
}
