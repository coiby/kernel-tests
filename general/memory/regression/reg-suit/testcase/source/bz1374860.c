#include <sys/types.h>
#include <sys/stat.h>
#include <sys/prctl.h>
#include <sys/mman.h>
#include <err.h>
#include <fcntl.h>
#include <stdio.h>
#include <signal.h>
#include <unistd.h>

# define PR_SET_MM_MAP			14

static volatile sig_atomic_t got_sigchld;
static int child;

static void
sigchld(int signo)
{

	got_sigchld = 1;
}

static void
sigterm(int signo)
{

	kill(child, 9);
}

int
main(void)
{
	struct prctl_mm_map prctl_map;
	char buf[80];
	char *p;
	int what, fd;

	signal(SIGCHLD, sigchld);
	signal(SIGTERM, sigterm);

	p = mmap(NULL, 4096, PROT_READ, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	if (p == MAP_FAILED)
		err(1, "mmap");

	prctl_map.start_code    = 0x400000;
	prctl_map.end_code      = 0x40096c;
	prctl_map.start_data    = 0x600e10;
	prctl_map.end_data      = 0x601054;
	prctl_map.start_brk     = 0x602000;
	prctl_map.brk           = 0x602000;
	prctl_map.start_stack   = 0x7fffffffe460;
	prctl_map.env_start     = 0x7fffffffe6d7;
	prctl_map.env_end       = 0x7fffffffe6df;
	prctl_map.auxv          = NULL;
	prctl_map.auxv_size     = 0;
	prctl_map.exe_fd        = -1;

	fd = open("/proc/self/cmdline", O_RDONLY);
	if (fd == -1)
		err(1, "open");

	child = fork();
	switch (child) {
	case -1:
		err(1, "fork");
	case 0:
		for (;;)
			read(fd, buf, sizeof(buf));
	default:
		what = 1;
		while (!got_sigchld) {
			prctl_map.arg_start = (__u64)((p + 1024) + (1024 * what));
			prctl_map.arg_end = (__u64)((p + 1024) + (1024 * what));
			what *= -1;

			//printf("%p %p\n", prctl_map.arg_start, prctl_map.arg_end);

			if (prctl(PR_SET_MM, PR_SET_MM_MAP, &prctl_map,
			    sizeof(prctl_map), 0) == -1) {
				kill(child, 9);
				err(1, "prctl");
			}
		}
	}

	return (1);
}

