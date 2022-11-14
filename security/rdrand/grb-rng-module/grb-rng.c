/*
 *  * Dummy RNG driver that uses get_random_bytes
 *
 * Copyright 2012 Red Hat
 * This file is licensed under the terms of the GNU General Public
 * License version 2. This program is licensed "as is" without any
 * warranty of any kind, whether express or implied.
 */

#include <linux/hw_random.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/random.h>

/* Choose whether to use get_random_bytes() or get_random_int() here */
#if 1
static int grb_rng_data_read(struct hwrng *rng, u32 *data)
{
#if defined (RHEL5) || defined (RHEL6)
	get_random_bytes(data, 4);
#elif defined (RHEL7) || defined (RHEL8) || defined (RHEL9)
	get_random_bytes_arch(data, 4);
#else
#error "Unknown RHEL release"	
#endif
	return 4;
}
#else
static int grb_rng_data_read(struct hwrng *rng, u32 *data)
{
	*data = get_random_int();
	return 4;
}
#endif

static int grb_rng_init(struct hwrng *rng)
{
	return 0;
}

static struct hwrng grb_rng = {
	.name		= "grb",
	.init		= grb_rng_init,
	.data_read	= grb_rng_data_read,
};

static int __init mod_init(void)
{
	int err = -ENODEV;

	err = hwrng_register(&grb_rng);
	if (err) {
		printk(KERN_ERR "Dummy RNG register failed (%d)\n", err);
	}
	return err;
}

static void __exit mod_exit(void)
{
	hwrng_unregister(&grb_rng);
}

module_init(mod_init);
module_exit(mod_exit);

MODULE_DESCRIPTION("get_random_bytes() dummy RNG driver");
MODULE_LICENSE("GPL");

