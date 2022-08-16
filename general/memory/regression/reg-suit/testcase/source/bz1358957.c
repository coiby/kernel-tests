#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/syscall.h>
#include <assert.h>
#include "SZ.h"


int main(int argc, const char *argv[])
{
    int ufd = syscall(__NR_userfaultfd, 0);
    assert(ufd > 0);

    char *mem = malloc(SZ);
    assert(mem);
    memset(mem, 0, SZ);

    execl("/proc/self/exe", "", NULL);
}
