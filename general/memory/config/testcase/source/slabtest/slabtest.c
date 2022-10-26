#include <linux/err.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/slab.h>


struct kmem_cache *slabtest_cache = NULL;
void *slabtest_buf = NULL;



static int __init slabtest_init(void)
{
    printk(KERN_ERR "init slabtest");
    slabtest_cache = kmem_cache_create("slabtest-32", 32, 0, 0, NULL);
    if (!slabtest_cache)
    {   printk(KERN_ERR "init slabtest failed");
        return -ENOMEM;
    }
    slabtest_buf = kmem_cache_zalloc(slabtest_cache, GFP_KERNEL);
    if (!slabtest_buf)
    {   printk(KERN_ERR "init slabtest failed");
        return -ENOMEM;
    }

    return 0;
}

static void __exit slabtest_cleanup(void)
{
    printk(KERN_ERR "cleanup slabtest");
    kmem_cache_free(slabtest_cache, slabtest_buf);
    kmem_cache_destroy(slabtest_cache);
}



#define DRV_LICENSE "GPL"
MODULE_LICENSE(DRV_LICENSE);
module_init(slabtest_init);
module_exit(slabtest_cleanup);
