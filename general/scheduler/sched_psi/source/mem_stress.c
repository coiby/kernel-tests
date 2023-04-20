// Allocate the max amount of memory possible at once to create a bit of memory
// pressure. 

#define _DEFAULT_SOURCE
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>


const int usecs_per_second = 1000000;
const int sleep_usecs = 10*usecs_per_second;
const int oom_score_amount = 1000;

const int NUM_THREADS = 4;

unsigned long long get_total_memory()
{
    long pages = sysconf(_SC_PHYS_PAGES);
    long page_size = sysconf(_SC_PAGE_SIZE);
    return pages * page_size;
}

void alloc_mem() {
    void * mem_ptr;

    //mmap the max amount of memory possible
    unsigned long long total_memory = get_total_memory()/2 + 4096;
    
    mem_ptr = 
        mmap(
            NULL,
            total_memory,PROT_READ | PROT_WRITE, 
            MAP_PRIVATE | MAP_ANON | MAP_LOCKED,
            0,
            0
        );

    usleep(sleep_usecs);

    munmap(mem_ptr,total_memory);
}

int main() {
    pid_t pids[NUM_THREADS];
    char filename[1000];
    void * oom_adjust_file;
    pid_t pid;

    // increase the oom_adjust_score so this process will get killed by
    // the oomkiller
    //
    // somtimes the test framework has had important bits killed instead,
    // so this should prevent that

    pid = getpid();
    sprintf(filename,"/proc/%d/oom_score_adj",pid);
    oom_adjust_file = fopen(filename,"w");
    fprintf(oom_adjust_file,"%d",oom_score_amount);

    fclose(oom_adjust_file);

    // spawn a second thread to make this faster
    for(int i=0; i<NUM_THREADS; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            alloc_mem();
            return 0;
        } else {
            pids[i] = pid;
        }

    }

    // wait for all child threads to finish up
    for(int i=0; i<NUM_THREADS; i++) {
        waitpid(pids[i],NULL,0);
    }


    return 0;
}




