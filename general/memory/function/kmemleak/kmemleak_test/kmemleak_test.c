/**
 * This kernel module determines whether the Kernel memory leak checker is
 * working.  This does a mem alloc without resreving the returned ptr when it's
 * loaded into the kernel.  If kmemleak is enabled (kmemleak=on) then kmemleak
 * should report the leak info in debugfs.
 */

#include <linux/err.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/slab.h>

static unsigned long *ptrs[4];

static int __init kmemleak_test_init(void)
{
        int i;

        printk(KERN_ERR "init kmemleak test");

        ptrs[0] = kmalloc(8, GFP_KERNEL);
        ptrs[1] = kmalloc(16, GFP_KERNEL);
        ptrs[2] = kmalloc(24, GFP_KERNEL);
        ptrs[3] = kmalloc(8192, GFP_KERNEL);
        for (i=0; i<4; i++) {
                *ptrs[i] = 0xdeadbeafUL + i;
                ptrs[i] = 0;
        }
        return 0;
}

static void __exit kmemleak_test_cleanup(void)
{
	printk(KERN_ERR "exit kmemleak test");
}


module_init(kmemleak_test_init);
module_exit(kmemleak_test_cleanup);
