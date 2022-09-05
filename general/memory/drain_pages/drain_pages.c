#include <linux/init.h>
#include <linux/module.h>

#include <linux/gfp.h>
#include <linux/mmzone.h>
#include <linux/slab.h>

#include <linux/kthread.h>

#define SECS_WAIT (60)
#define DRAIN_ORDER (MAX_ORDER - 2)

static unsigned int drain_order = DRAIN_ORDER;
module_param(drain_order, uint, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);
MODULE_PARM_DESC(drain_order, "the __get_free_pages order.");

static int debug = 0;
module_param(debug, int, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);
MODULE_PARM_DESC(drain_order, "show page alloc and free logs.");


struct pages_hdr {
	unsigned long addr;
	struct list_head list;
};

static struct task_struct *drain_thread = NULL;
static signed long jiffies_scan_wait;

static LIST_HEAD(pages_list);

static int drain_pages_thread(void *arg);
static void start_drain_thread(void);
static unsigned long drain_pages(unsigned int order);

static void free_drain_pages(unsigned long num, unsigned int order);
static void free_all_drain_pages(unsigned int order);



static int drain_pages_thread(void *arg)
{
	pr_warn("%sE", __func__);
	while (!kthread_should_stop()) {
		signed long timeout = jiffies_scan_wait;
		unsigned long total = 0;
		total = drain_pages(drain_order);
		free_drain_pages(total / 5, drain_order);

		/* wait before the next scan */
		while (timeout && !kthread_should_stop())
		{
			timeout = schedule_timeout_interruptible(timeout);
		}

		free_all_drain_pages(drain_order);
		timeout = jiffies_scan_wait;
		/* wait before the next scan */
		while (timeout && !kthread_should_stop())
		{
			timeout = schedule_timeout_interruptible(timeout);
		}
	}

	pr_warn("%sX", __func__);
	return 0;
}


static void start_drain_thread(void)
{
	pr_warn("%sE", __func__);
	if (drain_thread)
		return;

	drain_thread = kthread_run(drain_pages_thread, NULL, "drain_pages");
	if (IS_ERR(drain_thread)) {
		pr_warn("Failed to create the drain thread\n");
		drain_thread = NULL;
	}    
	pr_warn("%sX", __func__);
}


static unsigned long drain_pages(unsigned int order)
{
	unsigned long addr, total = 0;
	pr_warn("%sE", __func__);
	do {
		struct pages_hdr *hdr;
		addr = __get_free_pages(GFP_KERNEL | __GFP_ZERO, order);
		if (!addr)
			break;

		hdr = (struct pages_hdr*)kmalloc(sizeof(struct pages_hdr), GFP_KERNEL);
		if (!hdr)
		{
			free_pages(addr, order);
			break;
		}
		hdr->addr = addr;
		if (debug)
			pr_warn("%s, addr=%p, order=%u", __func__, (void*)hdr->addr, order);
		INIT_LIST_HEAD(&hdr->list);
		list_add_tail(&hdr->list, &pages_list);
		total++;
	} while (addr != 0);
	pr_warn("%sX, order=%u, total=%lu", __func__, order, total);
	return total;
}


static void free_drain_pages(unsigned long num, unsigned int order)
{
	int skipflag = 0;
	struct pages_hdr *hdr, *n;
	pr_warn("%sE, num=%lu\n", __func__, num);
	list_for_each_entry_safe(hdr, n, &pages_list, list) {
		if (num == 0)
			break;
		if (skipflag)  // do not free continous pages
		{
			skipflag = 0;
			continue;
		}
		if (debug)
			pr_warn("%s, addr=%p, order=%u\n", __func__, (void*)hdr->addr, order);
		free_pages(hdr->addr, order);
		num--;
		list_del(&hdr->list);
		kfree(hdr);
		skipflag = 1;
	}
	pr_warn("%sX", __func__);
}

static void free_all_drain_pages(unsigned int order)
{
	struct pages_hdr *hdr, *n;
	pr_warn("%sE", __func__);
	list_for_each_entry_safe(hdr, n, &pages_list, list) {
		if (debug)
			pr_warn("%s, addr=%p, order=%u\n", __func__, (void*)hdr->addr, order);
		free_pages(hdr->addr, order);
		list_del(&hdr->list);
		kfree(hdr);
	}
	pr_warn("%sX", __func__);
}


static int drainer_init(void)
{
	jiffies_scan_wait = msecs_to_jiffies(SECS_WAIT * 1000);
	start_drain_thread();
	return 0;
}


static void drainer_exit(void)
{
	if (drain_thread)
	{
		kthread_stop(drain_thread);
		drain_thread = NULL;
	}
	free_all_drain_pages(drain_order);
	pr_warn("%s", __func__);
}


module_init(drainer_init);
module_exit(drainer_exit);

MODULE_LICENSE("GPL");
