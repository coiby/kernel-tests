/*  
 *  Test case for machine checks in kernel code
 */
#include <linux/module.h>	/* Needed by all modules */
#include <linux/kernel.h>	/* Needed for KERN_INFO */
#include <linux/slab.h>
#include <linux/debugfs.h>
#include <asm/string_64.h>

static char *p;

static struct dentry *mctest;
static phys_addr_t phys;

static int srcoffset = 0;
module_param(srcoffset, int, 0);

#define MAGIC 0x417765736f6d6521

int init_module(void)
{

	if (srcoffset < 0 || srcoffset > 504) {
		printk(KERN_INFO "illegal srcoffset parameter\n");
		return -EINVAL;
	}

	mctest = debugfs_create_dir("mctest", NULL);
	debugfs_create_x64("addr", S_IRUSR, mctest, &phys);

	p = kmalloc(4096, GFP_KERNEL);

	*(u64 *)(p + 1024) = MAGIC;

	/* Injection address 1K into the page */
	phys = virt_to_phys(p + 1024);

	/* 
	 * A non 0 return means init_module failed; module can't be loaded. 
	 */
	return 0;
}

void cleanup_module(void)
{
	int r;

	/* begin copy before the poison, but always hit it at some point */
	r = memcpy_mcsafe(p+2048, p + 1024 - srcoffset, 512);

	if (r != 0) {
		printk(KERN_INFO "fault! %d\n", r);
		/* Don't free poisoned page! */
	} else {
		/* check for magic */
		if (*(u64 *)((p + 2048 + srcoffset)) == MAGIC)
			pr_info("Successful copy\n");
		else
			pr_info("No fault - but data not copied correctly\n");
		kfree(p);
	}
	debugfs_remove_recursive(mctest);
}

MODULE_LICENSE("GPL");
