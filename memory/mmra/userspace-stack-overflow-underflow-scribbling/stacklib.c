/*
 * Functions used by both userspace and kernelspace testing of stack
 * overflow/underflow/scribbling
 */

static int i;

static void f(void)
{
    f();
}

void overflow(void)
{
    f();
}

void underflow(void)
{
    /* The index is not declared here as stack manipulation
       below will reach to it and indirection will cause
       a misaligned read on aarch64 (Bus error) */
    /* Pop beyond the stack start */
    for (i = 0; i < (256*256); i++) {
        #if defined(__x86_64__)
            asm("pop %rax");
        #elif defined(__aarch64__)
            asm("ldr x0, [sp, #0]");
            asm("add sp, sp, 16");
        #else
            #error "Architecture not supported by the test"
        #endif
    }
    /* We would never get to this line */
}

static int scribbling_iter(int iteration)
{
    /* Write a random value to the previous position in the stack */
    #if defined(__x86_64__)
        asm("movq $0x12345679, 16(%rsp)");
    #elif defined(__aarch64__)
        asm("mov x0, #1234");
        asm("str x0, [sp, #48]");
    #else
        #error "Architecture not supported by the test"
    #endif
    /* SEGFAULT will happen when retrieving the return value and trying
     * to set ip to it */
    if (!iteration) {
        return 0;
    }
    /* Or when trying to call another function */
    scribbling_iter(iteration--);
    return 0;

}

void scribbling(void)
{
	scribbling_iter(1);
}

