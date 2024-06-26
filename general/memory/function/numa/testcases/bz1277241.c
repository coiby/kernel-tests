#include <unistd.h>
#include <sys/timeb.h>
#include <sched.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <sched.h>
#include <sys/shm.h>
#include <errno.h>
#include <stdint.h>
#include <signal.h>
#include <sys/syscall.h>

pthread_mutex_t AllocMutex;
pthread_cond_t AllocCond;
int only_one_thread_allocating_at_a_time=0;

typedef unsigned long long int UINT64;
pthread_t td[1024];
UINT64 len;
int strict_flag=1;
volatile int numthds=0;

char *GrabMemoryFromNumaNode(UINT64 len, int nodeid);

unsigned int allocmem(void* p)
{
    int locked=0;
    char *buf;

    if (only_one_thread_allocating_at_a_time) {
        locked=1;
        pthread_mutex_lock(&AllocMutex);
    }
    buf = GrabMemoryFromNumaNode(len, 1); // nodeid is hardcoded to 1 for this test
    memset(buf, 's', len);
    if (!locked) pthread_mutex_lock(&AllocMutex);
    numthds--; // we need the lock to decrement number of threads
    pthread_mutex_unlock(&AllocMutex);

    if (numthds <=0) pthread_cond_signal(&AllocCond);
    pthread_mutex_unlock(&AllocMutex);

}
char *GrabMemoryFromNumaNode(UINT64 len, int nodeid)
{
    char* buf=NULL;
    int i;
    long status;
    unsigned long mask[4];
    unsigned int bits_per_UL = sizeof(unsigned long)*8;

    for (i=0; i < 4; i++) mask[i]=0;
    mask[nodeid/bits_per_UL] |= 1UL << (nodeid % bits_per_UL);

    buf = (char*)mmap(0, len, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, 0, 0);
    if (buf == NULL) { printf("Unable to mmap\n"); return buf; }
    status = syscall(__NR_mbind, buf, len, 2, &mask, nodeid+2, 1);
    if (status != 0) {
        perror("alloc_mem_onnode(): unable to mbind: ");
        return NULL;
    }
    return buf;
}

int main(int argc, char** argv)
{
    long long freep;

    UINT64 mem0, mem1;	
    int i=0;
    if (argc != 4)
    {
        printf("usage: numat <#thread> <len-in-MB> <one-thd-alloc>\n");
        exit(1);
    }
    int numcpus = atoi(argv[1]);
    len = atoi(argv[2]);
    only_one_thread_allocating_at_a_time = atoi(argv[3]);

    pthread_mutex_init(&AllocMutex, NULL);
    pthread_cond_init(&AllocCond, NULL);

    printf("numcpus=%d, len=%d MB\n", numcpus, len);
    len = len*(UINT64)1024*(UINT64)1024;

    for (i=0; i < numcpus; i++)
    {
        int rc = pthread_create(&td[i], NULL, (void*)allocmem, NULL);
    }
    pthread_mutex_lock(&AllocMutex);
    pthread_cond_wait(&AllocCond, &AllocMutex);
    pthread_mutex_unlock(&AllocMutex);
    printf("Allocation is complete\n");

    sleep(300);

    return 0;
}
