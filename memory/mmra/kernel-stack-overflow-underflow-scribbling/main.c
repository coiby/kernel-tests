#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

#include <linux/delay.h>
#include <linux/interrupt.h>
#include "stacklib.h"

#define DRIVER_AUTHOR "RHIVOS QE"
#define DRIVER_DESC   "Stack manipulation (underflow/overflow/scribbling) test KMOD"

static char *testmode = "unset";
module_param(testmode, charp, 0660);

enum mode {
    OVERFLOW,
    UNDERFLOW,
    SCRIBBLING
} test_mode;

static void tasklet_fn(struct tasklet_struct *ts)
{
    pr_info("Example tasklet starts\n");
    mdelay(10000);
    switch (test_mode) {
        case OVERFLOW:
			overflow();
            break;
        case UNDERFLOW:
            underflow();
            break;
        case SCRIBBLING:
			scribbling();
            break;
        default:
            pr_info("Unknown test mode requested\n");
            break;
    }
    pr_info("Example tasklet ends\n");
}

DECLARE_TASKLET(mytask, tasklet_fn);

static int __init init_underflow(void)
{
    printk(KERN_INFO "underflow test module init testmode=%s\n", testmode);
    if (!strcmp(testmode, "overflow")) {
        test_mode = OVERFLOW;
    } else if (!strcmp(testmode, "underflow")) {
        test_mode = UNDERFLOW;
    } else if (!strcmp(testmode, "scribbling")) {
        test_mode = SCRIBBLING;
    } else {
        pr_info("Unknown or unset test mode: %s. ", testmode);
        pr_info("Load module with insmod stackman.ko testmode=[overflow|underflow|scribbling]\n");
        return -1;
    }
    tasklet_schedule(&mytask);
    pr_info("uderflow test module init continues...\n");
    return 0;
}
 
static void __exit cleanup_underflow(void)
{
    printk(KERN_INFO "underflow test module cleanup\n");
    tasklet_kill(&mytask);
}

module_init(init_underflow);
module_exit(cleanup_underflow);

MODULE_LICENSE("GPL");
MODULE_AUTHOR(DRIVER_AUTHOR);
MODULE_DESCRIPTION(DRIVER_DESC);
MODULE_VERSION("1.0.0");
