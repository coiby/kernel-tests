#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/vmalloc.h>
#include <linux/moduleparam.h>

MODULE_LICENSE("GPLv2");

static char *vm_buf;
static int vm_buf_size = 256;
module_param(vm_buf_size, int, S_IRUSR);

static int __init kg_vmalloc_init(void)
{
        pr_info("kg_vmalloc init\n");

        // Allocate vm_buf_size number of pages
        vm_buf = vmalloc(vm_buf_size * PAGE_SIZE);

        if (!vm_buf)
                pr_warn("%d pages' vmalloc fail\n", vm_buf_size);

        return 0;
}

static void __exit kg_vmalloc_exit(void)
{
        pr_info("kg_vmalloc exit\n");
        vfree(vm_buf);
}

module_init(kg_vmalloc_init);
module_exit(kg_vmalloc_exit);
