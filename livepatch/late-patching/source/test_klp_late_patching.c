/*
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 *
 *   test_klp_late_patching: livepatch module
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
#include <linux/livepatch.h>

void livepatch_target_module_func(void)
{
        pr_info("%s: livepatched", __func__);

        msleep(20);

        pr_info("%s exit\n", __func__);
}


static struct klp_func funcs[] = {
        {
                .old_name = "target_module_func",
                .new_func = livepatch_target_module_func,
        }, { }
};

static struct klp_object objs[] = {
        {
                .name = "test_module_late_patching",
                .funcs = funcs,

        }, { }
};

static struct klp_patch patch = {
        .mod = THIS_MODULE,
        .objs = objs,
};

static int test_klp_late_patching_init(void)
{
        return klp_enable_patch(&patch);
}

static void test_klp_late_patching_exit(void)
{
}

module_init(test_klp_late_patching_init);
module_exit(test_klp_late_patching_exit);
MODULE_LICENSE("GPL");
MODULE_INFO(livepatch, "Y");
