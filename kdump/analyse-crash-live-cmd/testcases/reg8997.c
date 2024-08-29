#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/wait.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#define MEM_SIZE 2147483648

int main(int argc, char *argv[])
{
int *addr, *addr1;

addr = mmap(NULL, MEM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
if (addr == MAP_FAILED)
{ fprintf(stderr, "mmap() failed\n"); exit(EXIT_FAILURE); }

addr1 = memset(addr, 0, MEM_SIZE);
if (*addr1 == -1) { fprintf(stderr, "mmset() failed\n"); exit(EXIT_FAILURE); }
printf("2 GB memory filled with 0 by memset()\n");
sleep(10000);
}
