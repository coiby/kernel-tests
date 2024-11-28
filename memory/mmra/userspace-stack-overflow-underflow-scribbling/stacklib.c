#include "stacklib.h"

/*
 * Functions used by both userspace and kernelspace testing of stack
 * overflow/underflow/scribbling
 */

void overflow(void)
{
    /* Pop above the stack end */
    for (int i = 0; i < (256*256); i++) {
        #if defined(__x86_64__)
            asm volatile("push %rax");
        #elif defined(__aarch64__)
            asm volatile("str x0, [sp, #-16]!");
        #else
            #error "Architecture not supported by the test"
        #endif
    }
    /* We would never get to this line */
}

void underflow(void)
{
    /* The index is not declared here as stack manipulation
       below will reach to it and indirection will cause
       a misaligned read on aarch64 (Bus error) */
    /* Pop beyond the stack start */
    for (int i = 0; i < (256*256); i++) {
        #if defined(__x86_64__)
            asm volatile("pop %rax");
        #elif defined(__aarch64__)
	    /*
	     * Subtract 16 bytes from the current stack pointer. However,
	     * with the debug kernel, sometimes this operation doesn't
	     * lead to a 16-bit-aligned value, and this will cause a
	     * bus error. So let's do the following three instructions:
	     * - Take the value of sp - 16 and store the result in x0
	     * - Do a bitwise or to clear the least 16 significant bits
	     * - Copy the value of x0 into the sp register.
	     * The assembler doesn't like it if we do the orr operation
	     * against the sp register, so that's why it needs to be
	     * done against x0.
	     */
            asm volatile("sub x0, sp, #16\n" \
                         "orr x0, x0, #-16\n" \
                         "mov sp, x0");
        #else
            #error "Architecture not supported by the test"
        #endif
    }
    /* We would never get to this line */
}

#ifndef __KERNEL__
#define noinline __attribute__((noinline))
#endif

static noinline void do_scribbling(char *buf, int size)
{
    for (int i = 0; i < size; i++) {
        buf[i] = 'a';
    }
}

void scribbling()
{
    char buf[10];

    // Intentionally overflow the buffer and overwrite the return address.
    do_scribbling(buf, 20);
}
