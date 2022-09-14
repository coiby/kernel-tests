#include <linux/module.h>
#include <linux/delay.h>
#include <linux/kthread.h>

static int runtime = 5;
static pid_t pid;
static struct task_struct *p;

static int wakeup_thread(void *ptr)
{
	unsigned long delta = HZ * (unsigned long)runtime;
	unsigned long timeout = jiffies + delta;
	struct pid *p_struct;
	do {
		if (!pid) break;
		p_struct = find_get_pid(pid);
		if (p_struct) {
			p = get_pid_task(p_struct, PIDTYPE_PID);
			if (p) wake_up_process(p);
		}
		mdelay(1000);
	} while (time_before_eq(jiffies, timeout));
	pr_info("wakeup_test: thread exited ...");
	return 0;
}

static int init_wakeup_test(void)
{
	p = kthread_create(wakeup_thread, NULL, "wakeup-%ld", 0L);
	if (!p)
		return 0;
	wake_up_process(p);
	return 0;
}

static void exit_wakeup_test(void)
{
	printk("wakeup_test: unloading module\n");
}

module_init(init_wakeup_test);
module_exit(exit_wakeup_test);

MODULE_LICENSE("GPL");
module_param(runtime, int, 0444);
module_param(pid, int, 0444);
