#include <unistd.h>
#include <stdlib.h>
#include <signal.h>

int usr_interrupt = 0;

int main() {
	sigset_t mask, oldmask;
	sigemptyset (&mask);
	sigaddset (&mask, SIGUSR1);
	sigprocmask (SIG_BLOCK, &mask, &oldmask);

	while (!usr_interrupt)
		sigsuspend(&oldmask);

	sigprocmask(SIG_UNBLOCK, &mask, NULL);

	return 0;
}

