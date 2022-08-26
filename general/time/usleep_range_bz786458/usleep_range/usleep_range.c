#include <linux/init.h>
#include <linux/module.h>
#include <linux/time.h>
#include <linux/ktime.h>
#include <linux/delay.h>

#define MIN_USEC 1000
#define MAX_USEC 2000
#define MSEC 1    

#define  ERROR(prev,next) (prev.tv_sec > next.tv_sec || (prev.tv_sec == next.tv_sec && prev.tv_nsec > next.tv_nsec))
#define  COMPARE(prev,next) (prev.tv_sec == next.tv_sec)

static int __init usleep_TEST(void)
{
	int count=0;
	struct timespec64 prev;
	struct timespec64 next;
	unsigned long delta;  // nanoseconds
	
	printk(KERN_INFO "### usleep_range() start\n");

	ktime_get_real_ts64(&prev);
	usleep_range(MIN_USEC, MAX_USEC);
	ktime_get_real_ts64(&next);

	goto print;

msleep:
	printk(KERN_INFO "\n### msleep() start\n");
	
	ktime_get_real_ts64(&prev);
	msleep(MSEC);
	ktime_get_real_ts64(&next);
	count++;

print:
	printk(KERN_INFO "### Before time is %lld.%09ld\n", prev.tv_sec, prev.tv_nsec);
	printk(KERN_INFO "### After  time is %lld.%09ld\n", next.tv_sec, next.tv_nsec);

	if (ERROR(prev,next)) {
		printk(KERN_INFO "### Error .");
		return 1;
	}

	if (COMPARE(prev,next)) 
		delta = next.tv_nsec - prev.tv_nsec;
	else 
		delta = (next.tv_sec - prev.tv_sec) * NSEC_PER_SEC + next.tv_nsec - prev.tv_nsec;

	printk(KERN_INFO "=> Sleeping for %ld microseconds\n",delta / 1000);

	if (!count)
		goto msleep;

	return 0;
}

static void __exit  usleep_EXIT(void)
{
	printk(KERN_INFO "\n### module exit\n");
}

module_init(usleep_TEST);
module_exit(usleep_EXIT);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Dong Zhu");
MODULE_DESCRIPTION("usleep_range()");
