#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/mutex.h>
#include <linux/delay.h>
#include <linux/interrupt.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/kthread.h>

/*Author: Chunyu Hu <chuhu@redhat.com> */

static int runtime = 20;

static struct test_hung_task_data {
	struct mutex dead_lock;
	struct hrtimer hrtimer_release_mutex;
	long val;
} test_data;

static struct task_struct *p;

static int hung_task_thread(void *ptr)
{
	unsigned long delta = HZ * (unsigned long)runtime;
	unsigned long timeout = jiffies + delta;
	mutex_lock(&test_data.dead_lock);
	mutex_unlock(&test_data.dead_lock);
	do {
		schedule_timeout_uninterruptible(delta);
	} while (time_before_eq(jiffies, timeout));
	pr_info("hung_task_test: thread exited ...");
	return 0;
}

static enum hrtimer_restart test_hrtimer_free_mutex_func(struct hrtimer* hr)
{
	struct test_hung_task_data *td = container_of(hr,
		struct test_hung_task_data, hrtimer_release_mutex);
	td->val++;
	return HRTIMER_NORESTART;
}

static int init_hung_task_test(void)
{
	ktime_t ktime;
	ktime = ktime_set(runtime, 0); //20 seconds.

	pr_info("hung_task_test: loading module");

	pr_info("hung_task_test: init the mutex");
	mutex_init(&test_data.dead_lock);

	pr_info("hung_task_test: start a alarm for %d s", runtime);
	hrtimer_init(&test_data.hrtimer_release_mutex, CLOCK_MONOTONIC,
						HRTIMER_MODE_REL);
	test_data.hrtimer_release_mutex.function = test_hrtimer_free_mutex_func;
	hrtimer_start(&test_data.hrtimer_release_mutex, ktime,
					HRTIMER_MODE_REL);

	pr_info("hung_task_test: start a hung_task kthread");
	p = kthread_create(hung_task_thread, NULL, "hung_task-%ld", 0L);
	wake_up_process(p);
	p = kthread_create(hung_task_thread, NULL, "hung_task-%ld", 1L);
	wake_up_process(p);
	return 0;
}

static void exit_hung_task_test(void)
{
	ktime_t rem;
	if (hrtimer_active(&test_data.hrtimer_release_mutex)) {
		rem = hrtimer_get_remaining(&test_data.hrtimer_release_mutex);
#ifdef KTIME_OLD_VERSION
		printk("hung_task_test: hrtimer is active, remaining %lld secs",
			rem.tv64 / NSEC_PER_SEC);
#else
		printk("hung_task_test: hrtimer is active, remaining %lld secs",
			rem / NSEC_PER_SEC);
#endif
		hrtimer_cancel(&test_data.hrtimer_release_mutex);
	}

	pr_info("hung_task_test: hrtimer has been done...");
	printk("hung_task_test: unloading module\n");
}

module_init(init_hung_task_test);
module_exit(exit_hung_task_test);

MODULE_LICENSE("GPL");
module_param(runtime, int, 0444);
MODULE_PARM_DESC(runtime, "Test parameter...");
