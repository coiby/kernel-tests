#include <linux/version.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/vmalloc.h>

void *vmap_area = NULL;
unsigned int mb = 0;
module_param(mb, int, S_IWUSR | S_IRUGO);
unsigned int gb = 0;
module_param(gb, int, S_IWUSR | S_IRUGO);

int init_module(void)
{
	unsigned long bytes = mb << 20;

	bytes += gb * (1UL << 30);
	if (!bytes) {
		pr_warn("kvmalloc-test: cannot allocate 0 bytes."
			" set mb, or gb module parameters\n");
		return -1;
	}

        vmap_area = vmalloc(bytes);
	if (!vmap_area) {
		pr_warn("kvmalloc-test: vmalloc(%lu) has failed\n", bytes);
		return -1;
	}

	pr_info("kvmalloc-test: vmalloc(%lu) succeeded\n", bytes);

	return 0;
}

void cleanup_module(void)
{
	if (vmap_area)
		vfree(vmap_area);
}

MODULE_LICENSE("GPL");
