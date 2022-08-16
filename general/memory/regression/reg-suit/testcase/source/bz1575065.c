/*
 * Testcase for bz1575065
 * Author: Ping Fang <pifang@redhat.com>
 * Should trigger a crash on affected version
 */

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <numaif.h>
#include <errno.h>
#include <pthread.h>
#include <time.h>

#define MPOL_LOCAL 4

unsigned long available_nodemask[16] = {0};
unsigned int pagesize;
unsigned long nodel;
unsigned int version = 4; //default not include MPOL_LOCAL

typedef void *(*func) (void *);

void *addr;

void *get_policy(void *id)
{
	int mode, ret;
	unsigned long nodemask[16] = {0};

	while (1) {
		ret = get_mempolicy(&mode, nodemask, 1024, addr + 4 * pagesize, MPOL_F_ADDR);
		if(ret != 0)
			perror("get_mempolicy error");
	}

}

void compose_bind(unsigned long **nodemask, unsigned int *maxnode, int *mode)
{
	int tmp_mode;
	srand(time(NULL) * rand());
	tmp_mode = rand()%version; // mode rand from 0~3/4
	switch(tmp_mode)
	{
		case MPOL_DEFAULT: //must empty maxnode, nodemask
		case MPOL_LOCAL: //RHEL6 not implement
			*nodemask = NULL;
			*maxnode = 0;
			break;
		case MPOL_BIND:
		case MPOL_INTERLEAVE:
		case MPOL_PREFERRED:
			*nodemask = malloc(128);
rerand:
			**nodemask = rand()%nodel; //rand node
			**nodemask &= available_nodemask[0];
			if (**nodemask == 0) //bind could't specific 0
				goto rerand;
			*maxnode = 64;
			break;
		default:
			perror("mode error\n");
			break;
	}

	*mode = tmp_mode;
}

void *bind_policy(void *id)
{
	int ret, mode, maxnode;
	unsigned long *nodemask = NULL;

	while (1) {
		compose_bind(&nodemask, &maxnode, &mode);
		//bind addr to spec node.
		ret = mbind(addr + 4 * pagesize, pagesize, mode, nodemask, maxnode, 0);
		if(ret != 0)
		{
			fprintf(stderr, "mbind failed, mode is %d nodel is %lu\n", mode, nodel);
			if (nodemask)
				fprintf(stderr, "mask is %lu\n", *nodemask);
		}

	}

	return NULL;
}

void main(int argc, char *argv[])
{
	int i, ids[8];
	int opt, node, ret = 0;
	pagesize = sysconf(_SC_PAGESIZE);
	pthread_t thread_id[8] = {0};
	func funcs[2] = {bind_policy, get_policy};

	if (argc < 3) {
		fprintf(stderr, "Usage: %s -n nodenum [-v version]\n", argv[0]);
		exit(EXIT_FAILURE);
	}
	ret = get_mempolicy(NULL, available_nodemask, 1024, NULL, MPOL_F_MEMS_ALLOWED);
	if (ret !=0 )
		exit(EXIT_FAILURE);

	while ((opt = getopt(argc, argv, "n:v:")) != -1) {
		switch (opt) {
			case 'n':
				node = atoi(optarg);
				if (node < 2) {
					fprintf(stderr, "node number must bigger than 2\n");
					exit(EXIT_FAILURE);
				}
				if (node > 31) {
					fprintf(stderr, "case unsupport more than 31\n");
					exit(EXIT_FAILURE);
				}
				nodel = 2L << (node - 1);
				break;
			case 'v':
				version = atoi(optarg);
				break;
			default:
				fprintf(stderr, "Usage: %s -n nodenum [-v version]\n", argv[0]);
				exit(EXIT_FAILURE);
		}
	}

	//allocate some mem.
	addr = mmap(NULL, 1024 * pagesize, PROT_WRITE | PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	for (i = 0; i < 8; i++) {
		ids[i] = i;
		if(pthread_create(&thread_id[i], NULL, funcs[i%2], &ids[i]) != 0)
			perror("thread create error\n");
	}
	sleep(5);
}
