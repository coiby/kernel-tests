#include <linux/init.h>
#include <linux/module.h>
#include <linux/slab.h>


static void my_cache_alloc(void *obj)
{
	memset(obj, 0, 256);
}

struct kmem_cache *one;
struct kmem_cache *two;


static int my_init(void)
{
	one = kmem_cache_create("one", 256, L1_CACHE_BYTES, SLAB_HWCACHE_ALIGN,
				my_cache_alloc);
        if (!one)
                pr_err("failed to allocate one\n");

	/* It is valid two create two caches with the same name. */
	two = kmem_cache_create("one", 256, L1_CACHE_BYTES, SLAB_HWCACHE_ALIGN,
				my_cache_alloc);
        if (!two)
                pr_err("failed at alocate two\n");

	pr_err("one: %p\n", one);
	pr_err("two: %p\n", two);

	if (one)
		kmem_cache_destroy(one);

	/* Crash will occur when this fucntion is called */
	if (two)
		kmem_cache_destroy(two);

	return 0;
}

static void my_exit(void)
{
	return;
}

#define DRV_LICENSE "noGPL"
MODULE_LICENSE(DRV_LICENSE);
module_init(my_init);
module_exit(my_exit);

