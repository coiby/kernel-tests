#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/irqflags.h>
#include <linux/delay.h>
#include <linux/printk.h>
#include <linux/kern_levels.h>
#include <linux/kthread.h>
#include <linux/moduleparam.h>
#include <linux/kprobes.h>

int thread_function(void *id)
{
        local_irq_disable();
        for (;;)
                udelay(1);
        return 0;
}


struct kthread {
       unsigned long flags;
       unsigned int cpu;
       int (*threadfn)(void *);
       void *data;
       struct completion parked;
       struct completion exited;
#ifdef CONFIG_BLK_CGROUP
      struct cgroup_subsys_state *blkcg_css;
#endif
};

static inline struct kthread *to_kthread(struct task_struct *k)
{
       WARN_ON(!(k->flags & PF_KTHREAD));
       return (__force void *)k->set_child_tid;
}

struct task_struct *kthread_create_on_cpu(int (*threadfn)(void *data),
                                         void *data, unsigned int cpu,
                                         const char *namefmt)
{
       struct task_struct *p;

       p = kthread_create_on_node(threadfn, data, cpu_to_node(cpu), namefmt,
                                  cpu);
       if (IS_ERR(p))
               return p;
       kthread_bind(p, cpu);
       /* CPU hotplug need to bind once again when unparking the thread. */
       to_kthread(p)->cpu = cpu;
       return p;
}

int my_panic(void *id)
{
        panic("repro");
        return 0;
}

static int __init repro_init(void)
{
        struct task_struct *t = NULL;
        struct task_struct *tt = NULL;

        t = kthread_create_on_cpu(thread_function, NULL, 2, "repro");
        if (!t) {
                printk(KERN_INFO "Failed to create a kernel thread for repro\n");
                return -1;
        }

        tt = kthread_create_on_cpu(my_panic, NULL, 3, "mypanic");
        if (!tt) {
                printk(KERN_INFO "Failed to create a kernel thread for panic\n");
                return -1;
        }

        wake_up_process(t);
        mdelay(5000);
        wake_up_process(tt);

        return 0;
}

static void __exit repro_exit(void)
{
}

module_init(repro_init)
module_exit(repro_exit)
MODULE_LICENSE("GPL");

