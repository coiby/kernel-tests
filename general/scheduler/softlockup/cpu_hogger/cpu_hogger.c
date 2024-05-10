#include <linux/init.h>
#include <linux/module.h>
#include <linux/kthread.h>
#include <linux/delay.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/string.h>
#include <uapi/linux/sched/types.h>

#define MAX_SCHEDULER_CLASS_LENGTH 24

static struct task_struct *hogger_thread;
static int stop_hogging = 0;
// absolute timeout value
static unsigned long timeout_end;
static char scheduler_class_str[MAX_SCHEDULER_CLASS_LENGTH + 1] = "NORMAL";
static int sched_priority = 0;
static int preempt_disable_flag = 1;
// default timeout value of 60 seconds
static unsigned long timeout = 60;

module_param(stop_hogging, int, 0644);
// timeout parameter in seconds
module_param(timeout, ulong, S_IRUGO);
// sched class parameter as string
module_param_string(scheduler_class_str, scheduler_class_str, sizeof(scheduler_class_str), S_IRUGO);
// sched priority parameter
module_param(sched_priority, int, S_IRUGO);
// flag to specify whether to disable preemption
module_param(preempt_disable_flag, int, S_IRUGO);

// map string to scheduler class enum value
static int str_to_scheduler_class(const char *str)
{
	if (strcmp(str, "FIFO") == 0)
		return SCHED_FIFO;
	else if (strcmp(str, "RR") == 0)
		return SCHED_RR;
	else
		return SCHED_NORMAL;
}

static void stop_hogger_thread(void)
{
	if (hogger_thread) {
		kthread_stop(hogger_thread);
		pr_info("hogger thread stopped");
	}
}

static int hogger_function(void *data)
{
	pr_info("hogger thread started");

	if (preempt_disable_flag) {
		preempt_disable();
	}

	while (!kthread_should_stop()) {
		if (stop_hogging) {
			pr_info("hogging stopped by user");
			break;
		}

		if (timeout_end && time_after(jiffies, timeout_end)) {
			pr_info("timeout reached, stopping hogging");
			break;
		}
		// release CPU without yielding
		cpu_relax();
	}

	if (preempt_disable_flag)
		preempt_enable();

	hogger_thread = NULL;

	return 0;
}

static int __init hogger_init(void)
{
	pr_info("initializing hogger module");

	scheduler_class_str[MAX_SCHEDULER_CLASS_LENGTH] = '\0';
	timeout_end = jiffies + timeout * HZ;

	hogger_thread = kthread_run(hogger_function, NULL, "cpu_hogger_thread");
	if (IS_ERR(hogger_thread)) {
		pr_info("failed to create hogger thread");
		return PTR_ERR(hogger_thread);
	}

	struct sched_attr attr = {
		.size = sizeof(struct sched_attr),
		.sched_policy = str_to_scheduler_class(scheduler_class_str),
		.sched_priority = sched_priority,
		.sched_flags    = 0,
		.sched_nice = 0,
		.sched_runtime  =  0,
		.sched_deadline = 0,
		.sched_period   = 0,
	};

	int ret = sched_setattr_nocheck(hogger_thread, &attr);
	if (ret) {
		pr_warn("%s: failed to set %s:%d %d", __func__,
				scheduler_class_str, sched_priority, ret);
		kthread_stop(hogger_thread);
		hogger_thread = NULL;
		return 0;
	}

	pr_info("module parameters:");
	pr_info("stop_hogging: %d", stop_hogging);
	pr_info("timeout: %lu", timeout);
	pr_info("scheduler_class_str: %s", scheduler_class_str);
	pr_info("sched_priority: %d", sched_priority);
	pr_info("preempt_disable_flag: %d", preempt_disable_flag);

	return 0;
}

static void __exit hogger_exit(void)
{
	pr_info("exiting hogger module");
	stop_hogger_thread();
}

module_init(hogger_init);
module_exit(hogger_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("chuhu@redhat.com");
MODULE_DESCRIPTION("Kernel module for CPU hogging with timeout, scheduler class, priority, and preempt_disable parameters");

