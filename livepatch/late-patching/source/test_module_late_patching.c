/*
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 *
 *   test_module_late_patching: target module
 *   Description: Livepatch late kernel module patching test
 *   Author: Yulia Kopkova <ykopkova@redhat.com>
 *
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 *   Copyright (c) 2022 Red Hat, Inc.
 *
 *   This program is free software: you can redistribute it and/or
 *   modify it under the terms of the GNU General Public License as
 *   published by the Free Software Foundation, either version 2 of
 *   the License, or (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be
 *   useful, but WITHOUT ANY WARRANTY; without even the implied
 *   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 *   PURPOSE.  See the GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program. If not, see http://www.gnu.org/licenses/.
 *
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/delay.h>

void target_module_func(void)
{
        pr_info("%s enter\n", __func__);

        msleep(20);

        pr_info("%s exit\n", __func__);
}

static int test_module_late_patching_init(void)
{
        pr_info("%s\n", __func__);
        target_module_func();

        return 0;
}

static void test_module_late_patching_exit(void)
{
        pr_info("%s\n", __func__);
}

module_init(test_module_late_patching_init);
module_exit(test_module_late_patching_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Yulia Kopkova <ykopkova@redhat.com>");
MODULE_DESCRIPTION("Target module for livepatch test");
