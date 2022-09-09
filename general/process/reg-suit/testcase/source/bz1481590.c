#include <unistd.h>
#include <signal.h>
#include <stdio.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <assert.h>

int main(void)
{
	int stat, pid = fork();
	siginfo_t si;

	if (!pid) {
		kill(getpid(), SIGSTOP);
		printf("EXIT!!!\n");
		return 0x13;
	}

	waitpid(pid, &stat, WSTOPPED);
	printf("stat=%x\n", stat);

	printf("INTR %d: ", pid);
	sleep(5);
	assert(0 == ptrace(PTRACE_SEIZE, pid, 0,0));

	assert(0 == ptrace(PTRACE_INTERRUPT, pid, 0,0));

	waitpid(pid, &stat, WSTOPPED);
	printf("stat=%x\n", stat);

	assert(0 == ptrace(PTRACE_GETSIGINFO, pid, NULL, &si));
	printf("sig=%d\n", si.si_signo);

	assert(0 == ptrace(PTRACE_CONT, pid, 0, 0));

	waitpid(pid, &stat, WSTOPPED);
	printf("stat=%x\n", stat);

	kill(pid, SIGKILL);
	if (pid == waitpid(pid, &stat, WSTOPPED))
		printf("stat=%x\n", stat);
	else {
		printf("gone %m\n");
		return 1;
	}
	return 0;
}

