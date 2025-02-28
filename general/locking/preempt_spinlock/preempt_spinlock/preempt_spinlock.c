#include <linux/module.h>
#include <linux/kthread.h>
#include <uapi/linux/sched/types.h>

/* run threads on cpu 0 */
static int cpu = 0;
static int flag = 0;
/* runtime 1s by default */
static unsigned long max_runtime = 0;
static unsigned long start_time = 0;

static struct task_struct *thread_locker;
static struct task_struct *thread_writer;

static spinlock_t test_spinlock;

static int thread_locker_func(void *data)
{
	spin_lock(&test_spinlock);
	/* wakeup writer thread to preempt current locker thread*/
	wake_up_process(thread_writer);
	while (!flag && time_before(jiffies, start_time + max_runtime)) {
		cpu_relax();
	}
	spin_unlock(&test_spinlock);
	while (!kthread_should_stop()) {
		schedule_timeout(msecs_to_jiffies(1000));
	}

	return 0;
}

static int thread_writer_func(void *data)
{
	flag = 1;
	pr_info("thread-writer successfully preempted the thread-locker");
	while (!kthread_should_stop()) {
		schedule_timeout(msecs_to_jiffies(1000));
	}

	return 0;
}

static int __init spinlock_preempt_test_init(void)
{
	int ret;
	struct sched_attr attr = {
		.size = sizeof(struct sched_attr),
		.sched_policy = SCHED_FIFO,
		.sched_priority = 1,
		.sched_flags    = 0,
		.sched_nice     = 0,
		.sched_runtime  = 0,
		.sched_deadline = 0,
		.sched_period   = 0,
	};
#ifdef CONFIG_PREEMPT_RT
	printk(KERN_INFO "PREEMPT_RT is enabled.\n");
#else
	printk(KERN_INFO "PREEMPT_RT is not enabled.\n");
#endif
	pr_info("Checking spin_lock() is converted to rtmutex in PREEMPT_RT and could be preempted.");
	pr_info("Threads bind to cpus %d\n", cpu);

	max_runtime = msecs_to_jiffies(1000);

	spin_lock_init(&test_spinlock);

	thread_locker = kthread_create_on_cpu(thread_locker_func, NULL, cpu, "thread-locker");
	if (IS_ERR(thread_locker)) {
		pr_err("Failed to create thread-locker\n");
		return PTR_ERR(thread_locker);
	}

	thread_writer = kthread_create_on_cpu(thread_writer_func, NULL, cpu, "thread-writer");
	if (IS_ERR(thread_writer)) {
		pr_err("Failed to create thread-writer\n");
		kthread_stop(thread_locker);
		return PTR_ERR(thread_writer);
	}

	ret = sched_setattr_nocheck(thread_writer, &attr);
	if (ret) {
		pr_warn("Failed to set thread_writer with SCHED_FIFO:1");
		kthread_stop(thread_writer);
		kthread_stop(thread_locker);
		thread_locker = NULL;
		thread_writer = NULL;
		return 0;
	}

	wake_up_process(thread_locker);

	start_time = jiffies;
	while (!flag && time_before(jiffies, start_time + max_runtime)) {
		cpu_relax();
	}

	if (!flag) {
		pr_info("FAIL: spin lock is not preempted in %u seconds by the high priority task\n", jiffies_to_msecs(max_runtime));
	} else {
		pr_info("PASS: spin lock is preempted in %u seconds by the high priority task\n", jiffies_to_msecs(max_runtime));
	}

	return 0;
}

static void __exit spinlock_preempt_test_exit(void)
{
	pr_info("spin_lock() preempt test module exiting\n");

	kthread_stop(thread_writer);
	kthread_stop(thread_locker);
}

module_init(spinlock_preempt_test_init);
module_exit(spinlock_preempt_test_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Test spin_lock(rtmutex) could be preempted in PREEMPT_RT");

