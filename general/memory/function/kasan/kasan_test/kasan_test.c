/**
 * This kernel module determines whether the Kernel-Address-Sanitizer (KASAN) is
 * enabled.  This does a read-after-free when it's loaded into the kernel.  If
 * KASAN is enabled then an error message should be printed to dmesg.
 */

#include <linux/err.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/slab.h>

MODULE_LICENSE ("GPL v2+");

static int __init kasan_test_init(void)
{
	char *ptr;
	printk(KERN_ERR "init kasan test");

	ptr = kmalloc(7, GFP_KERNEL);
	ptr[0] = 'F';
	ptr[1] = 'O';
	ptr[2] = 'O';
	ptr[3] = 'B';
	ptr[4] = 'A';
	ptr[5] = 'R';
	ptr[6] = 0;
	kfree(ptr);

	printk(KERN_ERR "Attempting read after free: %s.", ptr);
	return 0;
}

static void __exit kasan_test_cleanup(void)
{
	printk(KERN_ERR "exit kasan test");
}


module_init(kasan_test_init);
module_exit(kasan_test_cleanup);
