#define _GNU_SOURCE
#include <unistd.h>
#include <stdio.h>
#include <ucontext.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/types.h>

/* This is for trap into kernel detect.*/
/* https://bugzilla.redhat.com/show_bug.cgi?id=1629940 */

static unsigned long rip = 0xffffffff8f257d34;
void rip_construct(int sig, siginfo_t *info, void *context) 
{
#ifdef RHEL7
	struct ucontext *uc = context;
#else
	struct ucontext_t *uc = context;
#endif
	uc->uc_mcontext.gregs[REG_RIP] = rip;
}

int main(int argc, char** argv)
{
	if (argc > 1)
		rip = strtoul(argv[1], NULL, 16);
	struct sigaction a = {0};
	a.sa_flags = SA_SIGINFO|SA_ONSTACK;
	a.sa_sigaction = rip_construct;

	if (sigaction(SIGUSR1, &a, NULL))
		perror("sigaction");
	else
		puts("sigaction");

	if (kill(getpid(), SIGUSR1))
		perror("kill");
	return 0;
}

