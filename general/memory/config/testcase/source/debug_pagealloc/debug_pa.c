#include <linux/module.h>
#include <linux/slab.h>
#include <asm/page.h>

static char *p = NULL;

static int init_dummy(void)
{
    p = (char*)__get_free_pages(GFP_KERNEL, 2);
    pr_info("debug: alloc_page_addr=%p\n", p);
    return !p;
}

static void exit_dummy(void)
{
    pr_info("debug: free_page_addr=%p\n", p);
    free_pages((unsigned long)p, 2);
    pr_info("debug: access addr %p after free pages %ld.", p, *(long*)p);
}

module_init(init_dummy);
module_exit(exit_dummy);
MODULE_LICENSE("GPL");

