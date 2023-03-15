#!/bin/sh
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kdump/kdumpctl-options
#   Description: Test availability for kdumpctl options and regressions
#   Author: Ruowen Qin <ruqin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat
#
#   SPDX-License-Identifier: GPL-2.0-or-later WITH GPL-CC-1.0
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Include Beaker environment...

. ../include/runtest.sh

CheckUnexpectedReboot

rpm -q kexec-tools 2>/dev/null || InstallPackages kexec-tools

TESTARGS=${TESTARGS:-""}
SKIP_TESTARGS=${SKIP_TESTARGS:-""}

# Run Sub tests under testcases
RunSubTests "${TESTARGS}" "${SKIP_TESTARGS}"
