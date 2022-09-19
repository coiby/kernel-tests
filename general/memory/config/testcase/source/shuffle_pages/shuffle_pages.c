#include <linux/init.h>
#include <linux/module.h>
#include <linux/gfp.h>
#include <linux/mmzone.h>
#include <linux/slab.h>
#include <linux/kthread.h>
#include <linux/mm.h>

#define MILI_SECS_WAIT (200)
#define DRAIN_ORDER (MAX_ORDER - 1)

static int debug = 0;
static unsigned int shuffle_order = DRAIN_ORDER;
static unsigned long total;

module_param(shuffle_order, uint, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);
MODULE_PARM_DESC(shuffle_order, "the __get_free_pages order.");
module_param(debug, int, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);

static struct task_struct *shuffle_thread = NULL;
static signed long jiffies_scan_wait;

static int shuffle_pages_thread(void *arg);
static void start_shuffle_thread(void);
static unsigned long alloc_and_free_pages(unsigned int order);

static int shuffle_pages_thread(void *arg)
{
	unsigned long timeout;
	unsigned long pfn_num, pfn_last;
	unsigned long same_pfn, changed_pfn = 0;
	int reported = 40;

	pr_warn("%sE: shuffle thread started, order %d", __func__, shuffle_order);

	while (!kthread_should_stop()) {
		timeout = jiffies_scan_wait;
		pfn_num = alloc_and_free_pages(shuffle_order);
		if (pfn_num == pfn_last) {
			if (++same_pfn > 20 && reported != 0) {
				pr_warn("%sE: order %d: %s", __func__, shuffle_order, "Repeat 20 times of same pfn");
				reported--;
			}
		} else {
			same_pfn = 0;
			changed_pfn++;
		}
		pfn_last = pfn_num;
		/* wait before the next scan */
		while (timeout && !kthread_should_stop()) {
			timeout = schedule_timeout_interruptible(timeout);
		}
	}

	if (changed_pfn > 1)
		pr_warn("%sX: %s", __func__, "PASS");
	pr_warn("%sX: order=%u, total=%lu, changed_pfn=%lu\n", __func__, shuffle_order, total, changed_pfn);

	return 0;
}

static void start_shuffle_thread(void)
{
	if (shuffle_thread)
		return;

	shuffle_thread = kthread_run(shuffle_pages_thread, NULL, "shuffle_pages");
	if (IS_ERR(shuffle_thread)) {
		pr_warn("Failed to create the shuffle thread\n");
		shuffle_thread = NULL;
	}
}

static unsigned long alloc_and_free_pages(unsigned int order)
{
	unsigned long addr, pfn_num, flag;

	if (order > MAX_ORDER - 1)
		flag = __GFP_NOWARN;
	else
		flag = 0;

	addr = __get_free_pages(GFP_KERNEL | __GFP_ZERO | flag, order);
	if (!addr)
		return 0;

	pfn_num = __pa(addr) >> PAGE_SHIFT;

	if (debug)
		pr_warn("%s, addr=%p, pfn=%lu, order=%u", __func__, (void*)addr, pfn_num, order);
	free_pages(addr, order);
	total++;

	return pfn_num;
}

static int shuffleer_init(void)
{
	jiffies_scan_wait = msecs_to_jiffies(MILI_SECS_WAIT);
	start_shuffle_thread();
	return 0;
}

static void shuffleer_exit(void)
{
	if (shuffle_thread)
	{
		kthread_stop(shuffle_thread);
		shuffle_thread = NULL;
	}
}

module_init(shuffleer_init);
module_exit(shuffleer_exit);
MODULE_LICENSE("GPL");
