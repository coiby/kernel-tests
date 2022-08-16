#define _GNU_SOURCE
#include <sys/mman.h>
#include <asm-generic/mman.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <stdlib.h>
#include <errno.h>

#define PROT			PROT_READ|PROT_WRITE

#define REGION_PM_TMP_PATH	"/mnt/bz1842525/try_mremap"

#define REGION_MEM_SIZE 4096*4
#define REGION_PM_SIZE	4096*512
#define REMAP_MEM_OFF   0
#define REMAP_PM_OFF    0
#define REMAP_SIZE      4096

char * map_tmp_pm_region(void)
{
	int fd;

	fd = open(REGION_PM_TMP_PATH, O_RDWR|O_CREAT, 0644);
	if (fd < 0) {
		perror(REGION_PM_TMP_PATH);
		exit(-1);
	}

	if (ftruncate(fd, REGION_PM_SIZE)) {
		perror("ftruncate");
		exit(-1);
	}

	return mmap(NULL, REGION_PM_SIZE, PROT, MAP_SHARED_VALIDATE|MAP_SYNC,
			fd, 0);
}

int main(int argc, char **argv)
{
	char *regm, *regp, *remap;
	int ret;

	regm = mmap(NULL, REGION_MEM_SIZE, PROT, MAP_PRIVATE|MAP_ANONYMOUS,
			-1, 0);
	if (regm == MAP_FAILED) {
		perror("regm");
		return -1;
	}

	regp = map_tmp_pm_region();
	if (regp == MAP_FAILED) {
		perror("regp");
		return -1;
	}

	memset(regm, 'a', REGION_MEM_SIZE);
	memset(regp, 'i', REGION_PM_SIZE);

	remap = mremap(regp + REMAP_PM_OFF, REMAP_SIZE, REMAP_SIZE,
			MREMAP_MAYMOVE|MREMAP_FIXED, regm + REMAP_MEM_OFF);
	if (remap != regm + REMAP_MEM_OFF) {
		perror("mremap");
		return -1;
	}

	*regm = 0xAA;		/* write anything to the address */
	return 0;
}

