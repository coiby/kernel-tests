#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <getopt.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <sys/times.h>
#include <sys/types.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ipc.h>
#include <sys/shm.h>

#define SHM_KEY 0xbadbeef
#define MB	(1UL << 20)
#define OBJ_PERMS (S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP)
#define SHMGET_FAILED     (-1)
#define SHMAT_FAILED      ((void *) -1)
#define BALLOONMAP_RATIO 80
#define BALLOON_SIZE(v) (100 * v / BALLOONMAP_RATIO)

static inline void read_bytes(unsigned long length, void *addr)
{
	unsigned long i;
	unsigned char tmp;
	for (i = 0; i < length; i++)
		tmp += *((unsigned char *)(addr + i));
}

static inline void write_bytes(unsigned long length, void *addr)
{
	unsigned long i;
	for (i = 0; i < length; i++)
		*((unsigned char *)(addr + i)) = 0xff;
}

const char *prg_name;
const char *short_opts = "hs:";
const struct option long_opts[] = {
	{"help", 0, NULL, 'h'},
	{"shmsz", 1, NULL, 's'},
	{NULL, 0, NULL, 0} } ;

void print_usage(FILE *stream, int exit_code)
{
	fprintf(stream, "Usage: %s <options>\n", prg_name);
	fprintf(stream,
			"   -h  --help     (Display this usage information)\n"
			"   -s  --shmsz    <MB>\n"
			"   -w  --wait \n");
	exit(exit_code);
}

static inline void balloon_inflate(unsigned long len)
{
	void *addr = mmap(NULL, len, PROT_READ | PROT_WRITE,
			MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
	if (addr == MAP_FAILED) {
		perror("mmap");
		abort();
	}
	write_bytes(len, addr);
}

int main(int argc, char *argv[])
{
	int shmid, shm_flags = IPC_CREAT | IPC_EXCL | OBJ_PERMS;
	struct shmid_ds shm_buf;
	unsigned long shm_size;
	void *addr, *block;
	int errno, next_opt;

	shm_size = 0;
	prg_name = argv[0];
	do {
		next_opt = getopt_long(argc, argv, short_opts, long_opts, NULL);
		switch (next_opt) {
			case 's':
				shm_size = atoi(optarg) * MB;
				break;

			case 'h':
				print_usage(stdout, 0);

			case '?':
				print_usage(stderr, 1);

			case -1:
				break;

			default:
				abort();
		}
	} while (next_opt != -1);

	if (argc == 1 || shm_size == 0)
		print_usage(stderr, 2);

	printf("Setting up shmem seg 0x%x of %d bytes ...\n",
			SHM_KEY, shm_size);
	shmid = shmget(SHM_KEY, shm_size, shm_flags);
	if (shmid == SHMGET_FAILED) {
		perror("shmget");
		return 1;
	}

	addr = shmat(shmid, NULL, 0);
	if (addr == SHMAT_FAILED) {
		perror("shmat");
		return 1;
	}

	printf("Populating memory segment...\n");
	write_bytes(shm_size, addr);

	sleep(5);
	printf("Forcing swap usage...\n");
	balloon_inflate(BALLOON_SIZE(shm_size));
	sleep(1);

	printf("Reading shmem seg 0x%x back...\n", SHM_KEY);
	read_bytes(shm_size, addr);
	shmctl(shmid, IPC_RMID, &shm_buf);
	return 0;
}
