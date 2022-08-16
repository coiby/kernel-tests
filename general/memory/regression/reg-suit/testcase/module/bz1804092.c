/*
 * bz1804092-mod: simple exerciser module for Bug 1804092
 */
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/delay.h>

static void *data = NULL;

static int __init mod_init(void)
{
	int retcode = -ENOMEM;

	printk("KMALLOC_MAX_ORDER: %i\n", KMALLOC_MAX_ORDER);
	printk("KMALLOC_MAX_SIZE : %li\n", KMALLOC_MAX_SIZE);

	data = kmalloc(KMALLOC_MAX_SIZE, GFP_KERNEL);
	if (data)
		retcode = 0;

	return retcode;
}

static void __exit mod_exit(void)
{
	if (data)
		kfree(data);
}

module_init(mod_init);
module_exit(mod_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Rafael Aquini <aquini@redhat.com>");
MODULE_DESCRIPTION("BZ#1804092 simple exerciser module.");
MODULE_VERSION("1.0");
