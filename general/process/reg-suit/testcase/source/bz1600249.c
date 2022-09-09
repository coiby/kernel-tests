#define _GNU_SOURCE

#include <stdio.h>
#include <sched.h>

static inline unsigned long mfusprg()
{
	unsigned long rval;

	asm volatile("mfspr %0, 0x103" : "=r" (rval): );
	return rval;
}

int main ()
{
	printf("sched_getcpu() = %i\n", sched_getcpu());
	printf("SPR USPRG3 = %lx\n", mfusprg());

	return 0;
}
