#include<numa.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
int maps(unsigned long addr1, unsigned long addr2);
void printf_maps(unsigned long addr1, unsigned long addr2);
int main() {
	long int rand;
	unsigned int count;
	unsigned long i, addr2;
	int num_nodes;
	unsigned long addr1 =(unsigned long) mmap((void*)0x758200000, 0x10000000, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED, -1, 0);
	addr2 = addr1 + 0x10000000;
	printf("Start addr= %lx end addr= %lx pid= %d num_nodes: %d\n", addr1, addr2, count = getpid(), num_nodes = numa_num_configured_nodes());
	srandom(count);//randomly set the random seed
	while (1) {
		for (i = addr1, count = 0; i < addr2; i += (rand & ~0xfff)) {
			rand = random();
			rand %= addr2 - i;
			if(!(rand & ~0xfff)) {
				count++;//try 10 times..
				if(count < 10)
					continue;
				else
					break;
			}
			numa_tonode_memory((void*)i, (rand & ~0xfff), rand % num_nodes);
			printf("addr: %lx len: %ld node:%ld\n", i, (rand & ~0xfff), rand % num_nodes);
			if(!maps(addr1, addr2)) {
				printf("Hit the bug!!\n");
				printf_maps(addr1, addr2);
				return 0;
			}
		}
	}

	return 0;
}

void printf_maps(unsigned long addr1, unsigned long addr2) {

        FILE *fd;
        int ret;
        unsigned long first, second;

        char garbage[128];
        fd = fopen("/proc/self/maps", "r");

        do {
                ret = fscanf(fd, "%lx-%lx%[^\n]s",&first, &second, garbage);
        } while (ret != EOF && first < addr1);

        if (ret == EOF) {
                fclose(fd);
                return;
        }

        while (ret != EOF && second <= addr2) {
		if(first != addr1) {
			printf("This is where the problem is\n");
		}
		addr1 = second;
                printf("%lx - %lx\n",first, second);
                ret = fscanf(fd, "%lx-%lx%[^\n]s",&first, &second, garbage);
        }
        fclose(fd);
        return;
}

int maps(unsigned long addr1, unsigned long addr2) {

        FILE *fd;
        int ret;
        unsigned long first, second;

        char garbage[128];
        fd = fopen("/proc/self/maps", "r");

	do {
		ret = fscanf(fd, "%lx-%lx%[^\n]s",&first, &second, garbage);
	} while (ret != EOF && first < addr1);

	if (ret == EOF) {
		fclose(fd);
		return 0;
	}

        while (ret != EOF && second <= addr2) {
                //printf("%lx - %lx\n",first, second);
		if( first != addr1) {
			fclose(fd);
			return 0;
		}
		addr1 = second;
                ret = fscanf(fd, "%lx-%lx%[^\n]s",&first, &second, garbage);
        }
        fclose(fd);
        return 1;
}
