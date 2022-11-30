#define _GNU_SOURCE

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <pthread.h>

#define THREADCOUNT 8
#define PATHLIMIT 256
#define BUFSIZE 4096


#define LV1 "/dev/lvmraid/wrk"

struct params {
  char path[PATHLIMIT];
  char buffer[BUFSIZE];
};


struct params alloc_params(char *path) {
  struct params out;

  if (strlen(path) >= PATHLIMIT) {
    printf("supplied path too long\n");
    abort();
  }

  strncpy(&out.path[0], path, PATHLIMIT);
  memset(&out.buffer, 0, BUFSIZE);
  return out;
}

void *worker(void *data) {
  struct params *p = (struct params *) data;
  int counter = 0;
  ssize_t n = 0;

  int fd = open(p->path, O_RDONLY|O_DIRECT|O_CLOEXEC);
  if (fd == -1) return NULL;

  while (counter < 2048) {
    pread(fd, p->buffer, BUFSIZE, 0);
    counter++;
  }

  close(fd);
  return NULL;
}

int main(void) {
  struct params parray[THREADCOUNT] = {
    alloc_params(LV1),
    alloc_params(LV1),
    alloc_params(LV1),
    alloc_params(LV1),
  };
  pthread_t threads[THREADCOUNT];

  for (int i = 0; i < THREADCOUNT; i++) {
    int ret = pthread_create(&threads[i], NULL, worker, (void *)
  &parray[i]); if (ret!=0) {
      printf("failed to create thread: %d", ret);
      abort();
    }
  }
  for (int i = 0; i < THREADCOUNT; i++) {
    int ret = pthread_join(threads[i], NULL);
    if(ret!=0) {
      printf("failed to join thread: %d", ret);
      abort();
    }
  }

  return 0;
}
