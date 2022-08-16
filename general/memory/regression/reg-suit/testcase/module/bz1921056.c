#include <linux/module.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/kthread.h>
#include <linux/ctype.h>
#include <linux/vmalloc.h>
#include <linux/buffer_head.h>
#include <asm/uaccess.h>
#include <linux/slab.h>
#include <linux/version.h>

static ssize_t write_kmalloc512er(struct file *, const char __user *, size_t, loff_t *);
static int	kmalloc512er_run = 0;

static struct proc_dir_entry	*proc_kmalloc512er;
int expire_time;


static int repro(void *dummy)
{
	unsigned long count = 0;
	void *mem;

	printk(KERN_INFO "start repro\n");
	for (;;) {
		if (kmalloc512er_run == 0) break;
		mem = kmalloc_node(512, GFP_KERNEL, 0);
		if (mem != NULL)
			kfree(mem);
		count++;
		if (count % 1000000 == 0)
			schedule();
	}
	printk(KERN_INFO "exit repro(count: %ld)\n", count);
	return 0;
}

static int expire(void *dummy)
{
	unsigned long start_jiffies = jiffies;
	unsigned long expire_jiffies = start_jiffies + expire_time;

	printk(KERN_INFO "start expire\n");
	for (;;) {
		if (!kmalloc512er_run) break;
		if (expire_jiffies < jiffies) {
			kmalloc512er_run = 0;
			break;
		}
		set_current_state(TASK_INTERRUPTIBLE);
		schedule_timeout(HZ);
		set_current_state(TASK_RUNNING);
	}
	printk(KERN_INFO "exit expire\n");
	return 0;
}

static void start_repro(void)
{
	struct task_struct	*tsk;

	tsk = kthread_create(repro, NULL, "repro");
	if (!IS_ERR(tsk)) {
		kthread_bind(tsk, 0);
		wake_up_process(tsk);
		printk(KERN_INFO "create repro\n");
	}
	tsk = kthread_create(expire, NULL, "expire");
	if (!IS_ERR(tsk)) {
		kthread_bind(tsk, 0);
		wake_up_process(tsk);
		printk(KERN_INFO "create expire\n");
	}
}

static int kmalloc512er_proc_show(struct seq_file *m, void *v)
{
	printk(KERN_INFO "expire: %d\n", expire_time);
	return 0;
}

static int kmalloc512er_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, kmalloc512er_proc_show, PDE_DATA(inode));
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,6,0)
#define HAVE_PROC_OPS
#endif

#ifdef HAVE_PROC_OPS
struct proc_ops procops = {
	.proc_open = kmalloc512er_proc_open,
	.proc_read = seq_read,
	.proc_lseek = seq_lseek,
	.proc_release = single_release,
	.proc_write = write_kmalloc512er,
};
#else
struct file_operations procops = {
	.owner = THIS_MODULE,
	.open = kmalloc512er_proc_open,
	.read = seq_read,
	.llseek = seq_lseek,
	.release = single_release,
	.write = write_kmalloc512er,
};
#endif

static ssize_t write_kmalloc512er(struct file *file, const char __user *user_buf, size_t user_len, loff_t *pos)
{
	char	*buf;

	buf = vmalloc(user_len + 1);
	if (buf == NULL) {
		return -ENOMEM;
	}
	if (strncpy_from_user(buf, user_buf, user_len) < 0) {
		vfree(buf);
		return -EFAULT;
	}
	buf[user_len] = '\0';
	expire_time = simple_strtoul(buf, NULL, 10) * HZ;
	vfree(buf);
	if (kmalloc512er_run == 0) {
		kmalloc512er_run = 1;
		start_repro();
	}
	return user_len;
}

static void __init create_kmalloc512er_proc_entry(void)
{
	proc_kmalloc512er = proc_create_data("kmalloc512er", S_IRWXUGO, NULL, &procops, NULL);
}

static void __exit remove_kmalloc512er_proc_entry(void)
{
	remove_proc_entry("kmalloc512er", NULL);
}

static int __init kmalloc512er_init(void)
{
	create_kmalloc512er_proc_entry();
	kmalloc512er_run = 0;
	return 0;
}

static void __exit kmalloc512er_exit(void)
{
	kmalloc512er_run = 0;
	set_current_state(TASK_INTERRUPTIBLE);
	schedule_timeout(expire_time+HZ);
	remove_kmalloc512er_proc_entry();
}

MODULE_LICENSE("GPL");
module_init(kmalloc512er_init);
module_exit(kmalloc512er_exit);
