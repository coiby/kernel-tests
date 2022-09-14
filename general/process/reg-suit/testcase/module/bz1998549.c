#include <linux/init.h>
#include <linux/module.h>
#include <linux/slab.h>


static void my_cache_alloc(void *obj)
{
	return;
}

struct kmem_cache *one;
struct kmem_cache *two;


static int my_init(void)
{
	return 0;
}

static void my_exit(void)
{
	/* chuhu@: 2021-09-10 this is for testing bz1998549 */
	if (2) {
		rcu_read_lock();
		rcu_read_unlock();
	}

	return;
}

#define DRV_LICENSE "noGPL"
MODULE_LICENSE(DRV_LICENSE);
module_init(my_init);
module_exit(my_exit);

