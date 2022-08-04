#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>

#include <sys/ipc.h>
#include <sys/types.h>
#include <sys/wait.h>

#define ALIGN 512
#define WORKER_NUM 128
#define BUF_SIZE 512*(WORKER_NUM * 2)
#define READ_SIZE 512
#define PATTERN 7

#define HUGE_SIZE	(256 * 1024 * 1024)
#define HUGE_ALIGN(s)	(((s) + (HUGE_SIZE - 1)) & ~(HUGE_SIZE-1))
#define HUGEFILE	"/huge/testfile"

typedef struct {
	pthread_t	tid;
	int		fd;
	char		*buf;
	int		pattern;
} worker_t;

unsigned int bad_data_cnt;

void *pthread_fork(void *arg)
{
	pid_t pid;

	while (1) {
		pid = fork();

		if (pid == 0) {
			exit(1);
		} else if (pid < 0) {
			perror("fork");
			exit(1);
		}
		waitpid(pid, NULL, 0);
		usleep(1);
	}
}

void *worker_thread(void *arg)
{
	worker_t *worker = (worker_t *) arg;
	int fd = worker->fd;
	char *buf = worker->buf;
	int pattern = worker->pattern;
	int rd_res;
	int i,j;
	int cnt = 0;

	rd_res = read(fd, buf, READ_SIZE);
	if (rd_res != READ_SIZE) {
		perror("read");
		exit(1);
	}

	for (i = 0; i < READ_SIZE; i++) {
		if (buf[i] == pattern) {
			cnt++;
			if (cnt == (READ_SIZE -1)) {
				++ bad_data_cnt;
				/**
				 * comment these because the huge amount output to
				 * log will cause test case fail, because rhts
				 * is unable to upload the log.
				 */
				/*
				printf("Bad data\n");
				printf("rd_res = %d\n",rd_res);
				printf("pattern = %d\n", pattern);
				printf("buf = ");
				for (j = 0; j < 10; j++)
					printf("%d", buf[j]);
				printf("\n");
				*/
			}
		}
	}
}

int main(int argc, char **argv)
{
	int fd;	
	int rc;
	int i;
	pthread_t fork_tid;
	char *buf;
	worker_t *workers;

	/* argument check */
	if (argc != 2) {
		fprintf(stderr, "invalid argument.\n");
		exit(1);
	}

	workers = malloc(WORKER_NUM * sizeof(worker_t));
	if (workers == NULL) {
		perror("malloc");
		exit(1);
	}

	fd = open(HUGEFILE, O_RDWR|O_CREAT|O_TRUNC);
	if (fd < 0) {
		perror("open");
		exit(1);
	}
	buf = mmap(NULL, HUGE_ALIGN(BUF_SIZE), PROT_READ|PROT_WRITE,
			MAP_PRIVATE, fd, 0);
	if (buf == NULL) {
		perror("valloc");
		exit(1);
	}

	rc = pthread_create(&fork_tid, NULL, pthread_fork, NULL);
	if (rc != 0) {
		perror("pthread_create");
		exit(1);
	}

	while(1) {
		memset(buf, PATTERN, BUF_SIZE);

		fd = open(argv[1], O_RDONLY|O_DIRECT);
		if (fd < 0) {
			perror("open");
			exit(1);
		}

		for (i = 0; i < WORKER_NUM; i++) {
			workers[i].fd = fd;
			workers[i].buf = buf + ALIGN * i;
			workers[i].pattern = PATTERN;
		}

		for (i = 0; i < WORKER_NUM; i++) {
			rc = pthread_create(&workers[i].tid, NULL,
					    worker_thread, workers + i);
			if (rc != 0) {
				perror("pthread_create");
				exit(1);
			}
		}

		for (i = 0; i < WORKER_NUM; i++) {
			rc = pthread_join(workers[i].tid, NULL);
			if (rc != 0) {
				perror("pthread_join");
				exit(1);
			}

		}

		close(fd);
	}

	rc = pthread_join(fork_tid, NULL);
	if (rc != 0) {
		perror("pthread_join");
		exit(1);
	}

	free(buf);
	printf("bad data encountered %d times.\n", bad_data_cnt);
	return 0;
}
