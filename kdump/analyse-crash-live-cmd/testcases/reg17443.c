#include <linux/kernel.h>
#include <linux/module.h>

int var_non_static = 0;
static int var_static = 0;

static int test_init(void)
{
    var_non_static += 5;
    var_static += 5;
    printk(KERN_INFO "%d static=%d\n", var_non_static, var_static);
    return 0;
}

static void test_exit(void)
{
    var_non_static += 7;
    var_static += 7;
    printk(KERN_INFO "%d static=%d\n", var_non_static, var_static);
}

module_init(test_init);
module_exit(test_exit);
MODULE_LICENSE("GPL");