#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include "omp.h"

int main() 
{
	#pragma omp parallel	

	{
		size_t size = 55*1000*1000; // tweaked for 288cpus, "leaks" ~3.5GB
		void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS , -1, 0);
		if (p != MAP_FAILED)
			memset(p, 0, size);
			//munmap(p, size); // uncomment to make the problem go away
	}
	
	return 0;
}             
