#define _GNU_SOURCE 

#include <sys/syscall.h>
#include <unistd.h>
#include <pthread.h>
#include <stdlib.h>

#include <stdint.h>
#include <string.h>

long r[20];
void *thr(void *arg)
{
        switch ((long)arg) {
        case 0:
                r[0] = syscall(__NR_mmap, 0x20000000ul, 0xc14000ul, 0x3ul, 0x32ul, 0xfffffffffffffffful, 0x0ul);
                break;
        case 1:
*(uint64_t*)0x2000afa0 = (uint64_t)0x0;
*(uint32_t*)0x2000afa8 = (uint32_t)0x40000000;
*(uint32_t*)0x2000afac = (uint32_t)0x1;
*(uint64_t*)0x2000afb0 = (uint64_t)0x20764fff;
*(uint64_t*)0x2000afb8 = (uint64_t)0x20000fb0;
*(uint64_t*)0x2000afc0 = (uint64_t)0x0;
*(uint64_t*)0x2000afc8 = (uint64_t)0x0;
*(uint64_t*)0x2000afd0 = (uint64_t)0x0;
*(uint64_t*)0x2000afd8 = (uint64_t)0x0;
*(uint64_t*)0x2000afe0 = (uint64_t)0x0;
*(uint64_t*)0x2000afe8 = (uint64_t)0x0;
*(uint64_t*)0x2000aff0 = (uint64_t)0x0;
*(uint64_t*)0x2000aff8 = (uint64_t)0x0;
                r[14] = syscall(__NR_timer_create, 0x8ul, 0x2000afa0ul, 0x20009ffcul);
                break;
        case 2:
*(uint64_t*)0x205dafe0 = (uint64_t)0x77359400;
*(uint64_t*)0x205dafe8 = (uint64_t)0x0;
*(uint64_t*)0x205daff0 = (uint64_t)0x0;
*(uint64_t*)0x205daff8 = (uint64_t)0x989680;
                r[19] = syscall(__NR_timer_settime, 0x0ul, 0x0ul, 0x205dafe0ul, 0x20c11000ul);
                break;
        }
        return 0;
}

void loop()
{
        long i;
        pthread_t th[6];

        memset(r, -1, sizeof(r));
        for (i = 0; i < 3; i++) {
                pthread_create(&th[i], 0, thr, (void*)i);
                usleep(rand()%10000);
        }
        usleep(rand()%100000);
}

int main()
{
        loop();
        return 0;
}

