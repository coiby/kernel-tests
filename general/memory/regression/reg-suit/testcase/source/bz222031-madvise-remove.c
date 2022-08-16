#include <sys/mman.h>
#include <stdlib.h>
#include <stdio.h>

#ifndef MADV_REMOVE
#define MADV_REMOVE 9
#endif

int main(void)
{
	char *vma;

	vma = mmap(NULL, 4096, PROT_READ|PROT_WRITE,
			MAP_SHARED|MAP_ANONYMOUS, -1, 0);
	if (vma == MAP_FAILED)
		perror("mmap"), exit(1);

	if (madvise(vma, 8192, MADV_REMOVE) == -1)
		perror("madvise"), exit(1);
	perror("madvise succeeded.");
	if( vma )
		munmap(vma, 4096);
	exit(0);
}
