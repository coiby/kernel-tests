#define _GNU_SOURCE
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <assert.h>
#include <sys/ptrace.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
// 0x200000 does not reproduce it
#define SIZE_TO_MMAP 0x400000

int main(void) {

	setbuf(stdout, NULL);
	assert_perror(errno);
	void *addr = mmap(NULL, SIZE_TO_MMAP, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0);
	assert_perror(errno);
	assert(addr != MAP_FAILED);
	pid_t child = fork();

	switch (child) {
		case -1:
			assert_perror(errno);
			assert(0);
		case 0: {
				long l = ptrace(PTRACE_TRACEME, 0, NULL, NULL);
				assert_perror(errno);
				assert(l == 0);

				int i = raise(SIGUSR1);
				assert_perror(errno);
				assert(i == 0);

			} assert(0);

		default:
			break;
	}

	int status;

	pid_t got_pid = waitpid(child, &status, 0);

	assert_perror(errno);
	assert(got_pid == child);
	assert(WIFSTOPPED(status));
	assert(WSTOPSIG(status) == SIGUSR1);

	char *mem_fn;
	int i;

	i = asprintf(&mem_fn, "/proc/%d/mem", child);
	assert(i > 0);

	int fd = open(mem_fn, O_RDONLY);

	assert_perror(errno);
	assert(fd != -1);

	char *smaps_fn;

	i = asprintf(&smaps_fn, "perl -ne '$i=0 if /^[0-9a-f]/;$i=1 if /^%08zx-%08zx /;print if $i;' /proc/%d/smaps",
			(size_t)(uintptr_t)addr, (size_t)(uintptr_t)addr+SIZE_TO_MMAP, child);

	assert(i > 0);

	i = system(smaps_fn);
	assert(i == 0);

	static char readbuf[SIZE_TO_MMAP];
	assert(sizeof(off_t) == sizeof(uintptr_t));

	ssize_t got_read = pread(fd, readbuf, SIZE_TO_MMAP, (loff_t)(uintptr_t)addr);
	assert_perror(errno);
	assert(got_read == SIZE_TO_MMAP);

	i = system(smaps_fn);
	assert(i == 0);

	kill(child, SIGKILL);

	return 0;
}
