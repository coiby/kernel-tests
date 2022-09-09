#include <signal.h>
#include <syscall.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

int
rt_tsigqueueinfo(pid_t tgid, pid_t pid, int sig, siginfo_t *info)
{

	return (syscall(SYS_rt_tgsigqueueinfo, tgid, pid, sig, info));
}

int
main(void)
{
	siginfo_t info;
	pid_t child;
	int ret = -1;

	switch (child = fork()) {
	case -1:
		perror("fork");
		return (1);
	case 0:
		pause();
		_Exit(0);
	}

	memset(&info, 0, sizeof(info));
	info.si_code == SI_TKILL;
	info.si_signo = 0;

	ret = rt_tsigqueueinfo(child, child, 0, &info);
	perror("rt_sigqueueinfo");
	kill(child, 9);

	return (ret);
}
