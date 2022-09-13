#include <err.h>
#include <unistd.h>
#include <inttypes.h>
#include <errno.h>
#include <stdio.h>

int
main (void)
{
   errno = 0;
   void *p = sbrk (0);
   if (errno != 0)
     err (1, "sbrk (0)");
   printf ("initial brk value: %p\n", p);
   unsigned long long target = 0x800000020000ULL;
   if ((uintptr_t) p >= target)
     errx (1, "initial brk value is already above target");
   unsigned long long increment = target - (uintptr_t) p;
   errno = 0;
   sbrk (increment);
   if (errno != 0)
     err (1, "sbrk (0x%llx)", increment);
   volatile int *pi = (volatile int *) (target - 4);
   printf ("probing at %p\n", pi);
   *pi = 1;
}
