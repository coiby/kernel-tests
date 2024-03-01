// SPDX-License-Identifier: GPL-2.0

#define pr_fmt(fmt) "vkm: " fmt

#include <linux/version.h>
#include <linux/module.h>
#include <linux/printk.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/init.h>
#include <linux/vmalloc.h>
#include <linux/slab.h>
#include <linux/highmem.h>

static struct kobject *vkm_kobj;

#define VKM_ATTR_RO(_name) \
	static struct kobj_attribute _name##_attr = __ATTR_RO(_name)
#define VKM_ATTR_WO(_name) \
	static struct kobj_attribute _name##_attr = __ATTR_WO(_name)
#define PANIC_MSG "Trigger fault.\n"
#define MSG_BUFFER_LEN 16
#define NR_REQ 1

static ssize_t write_ro_crash_store(struct kobject *kobj,
				    struct kobj_attribute *attr,
				    const char *buf, size_t count)
{
	char *ro;
	struct page *page;

	page = virt_to_page(get_zeroed_page(GFP_KERNEL));
	if (!page)
		return -ENOMEM;

	ro = vmap(&page, 1, VM_MAP, PAGE_KERNEL_RO);
	if (!ro) {
		__free_page(page);
		return -ENOMEM;
	}
	// Initiate fault.
	*ro = '\0';

	pr_info("%s: FAIL:write_ro_crash\n.", __func__);

	vunmap(ro);
	__free_page(page);

	return count;
}
VKM_ATTR_WO(write_ro_crash);

static ssize_t write_um_crash_store(struct kobject *kobj,
                    struct kobj_attribute *attr,
                    const char *buf, size_t count)
{
    char *um;
    struct page *page;

    page = virt_to_page(get_zeroed_page(GFP_KERNEL));
    if (!page)
        return -ENOMEM;

    um = vmap(&page, 1, VM_MAP, PAGE_KERNEL);
    if (!um) {
        __free_page(page);
        return -ENOMEM;
    }
    vunmap(um);
    // Initiate fault.
    *um = '\0';
    pr_info("%s: FAIL:write_um_crash\n.", __func__);
    __free_page(page);

    return count;
}
VKM_ATTR_WO(write_um_crash);

static ssize_t null_crash_store(struct kobject *kobj, struct kobj_attribute *attr,
              const char *buf, size_t count)
{
    // Initiate fault.
    char c = *((char*)NULL);

    pr_info("%s: FAIL:null_crash (%c)\n.", __func__, c);

    return count;
}
VKM_ATTR_WO(null_crash);

static struct attribute *vkm_sysfs_entries[] = {
	&write_ro_crash_attr.attr,
	&write_um_crash_attr.attr,
	&null_crash_attr.attr,
	NULL
};

static const struct attribute_group vkm_attribute_group = {
	.attrs = vkm_sysfs_entries,
};

static int __init vkm_init(void)
{
	int rc;

	vkm_kobj = kobject_create_and_add("vkm", kernel_kobj);
	if (!vkm_kobj)
		return -ENOMEM;

	rc = sysfs_create_group(vkm_kobj, &vkm_attribute_group);
	if (rc) {
		pr_err("Failed to create sysfs attributes (%d).", rc);
		goto out;
	}

	return 0;

out:
	kobject_put(vkm_kobj);
	return rc;
}
module_init(vkm_init);

static void __exit vkm_exit(void)
{
	sysfs_remove_group(vkm_kobj, &vkm_attribute_group);
	kobject_put(vkm_kobj);
}
module_exit(vkm_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Eric Chanudet");
MODULE_DESCRIPTION("Deviant mapper causing faults in various circumstances.");
