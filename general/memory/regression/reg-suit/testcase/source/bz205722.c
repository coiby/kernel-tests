#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <string.h>

#include <iostream>

#define BUFSIZE 10485760
#define BUFFERS 1700

char *buffers[BUFFERS];
int child_num=0;

void *copy_block(void *);

int main(int argc, char **argv){
  int order=0;

  // make 8 procs
  while(order<7)
    switch(fork()){
    case -1:
      break;
    default:
      order++;
      break;
    case 0:
      child_num=order;
      order=8;
      break;
    }

  int random_fd=open("/dev/urandom",O_RDONLY);
  if(random_fd==-1)
    exit(1);

  int i;
  int retval=0;
  try{
    /* Why lots of buffers rather than one big buffer. It is my 
       expectation that this is the way that OpenMPI does it when
       it allocates its set of queue pair destinations. */
  
    for(i=0;i<BUFFERS;i++){
      buffers[i]=new char[BUFSIZE];
    }
    
    pthread_t copy_thread;
    pthread_create(&copy_thread,NULL,copy_block,NULL);

    /* Bang on them in a random order */
    for(i=0;i<BUFFERS;i++){
      int cur;
      while(buffers[cur=random()%BUFFERS][random()%BUFSIZE]==0)
	read(random_fd,buffers[cur],BUFSIZE);
      std::cout << 'a'+ child_num;
    }
  }
  catch(std::bad_alloc &e){
    std::cout << "failed allocating " << i << '\t'; 
    retval=2;
  }
  
  std::cout << getpid() <<'\n';
  exit(retval);
}

void *copy_block(void *){
  for(int i=0;i<BUFFERS/2;i++){
    int src;
    while(buffers[src=random()%BUFFERS][random()%BUFSIZE]==0);

    int dst;
    while(buffers[dst=random()%BUFFERS][random()%BUFSIZE]==0)
      memcpy(buffers[dst],buffers[src],BUFSIZE);
    std::cout << 'A'+ child_num;
  }
}
