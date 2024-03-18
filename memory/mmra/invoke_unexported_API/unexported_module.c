#include <linux/module.h>
#include <linux/kernel.h>

MODULE_DESCRIPTION("Test Module for Unexported Symbol");
MODULE_LICENSE("GPL");

extern void unexported_kernel_symbol(void);

static int __init unexported_test_module_init(void) {
    printk(KERN_INFO "Attempting to use an unexported kernel symbol.\n");
    unexported_kernel_symbol(); /* This should cause a compile/link-time error. */
    return 0;
}

static void __exit unexported_test_module_exit(void) {
    printk(KERN_INFO "Test module exit.\n");
}

module_init(unexported_test_module_init);
module_exit(unexported_test_module_exit);
