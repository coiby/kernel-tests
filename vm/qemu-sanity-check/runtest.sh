#!/bin/bash

#-----------------------------------------------------------------------------
# Copyright (c) 2023 Red Hat, Inc. All rights reserved. This
# copyrighted material is made available to anyone wishing to use,
# modify, copy, or redistribute it subject to the terms and conditions
# of the GNU General Public License v.2.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.
#
# Author: Richard W.M. Jones <rjones@redhat.com>
#-----------------------------------------------------------------------------
#
#	Simple test: does the kernel boot on top of qemu-kvm?
#
#-----------------------------------------------------------------------------

# Source the common test script helpers
. ../../cki_lib/libcki.sh || exit 1

# qemu-sanity-check comes from EPEL, we may have to install that first.
if ! rpm -q epel-release; then
    dnf install -y  https://dl.fedoraproject.org/pub/epel/epel-release-latest-"$(rpm -E '%rhel')".noarch.rpm
    need_remove=1
else
    param="--enablerepo=epel"
fi

# shellcheck disable=SC2086 # disabled on purpose as we want param to expand
dnf install -y $param qemu-sanity-check
[ "${need_remove}" ] && dnf -y remove epel-release

# qemu-sanity-check should be installed.
rpm -q qemu-sanity-check ||
    cki_abort_task "qemu-sanity-check is not installed"

# Try to load kvm module
modprobe kvm || true

# Boot the kernel using KVM.
if [ -r /dev/kvm ]; then
    qemu-sanity-check --accel=kvm | tee kvm.log
    if [[ ${PIPESTATUS[0]} == 0 ]]; then
        rstrnt-report-result -o kvm.log kvm PASS
    else
        rstrnt-report-result -o kvm.log kvm FAIL
    fi
else
    rstrnt-report-result kvm SKIP
fi

# Boot the kernel using TCG (software emulation).
qemu-sanity-check --accel=tcg --cpu=max -t 20m | tee tcg.log
if [[ ${PIPESTATUS[0]} == 0 ]]; then
    rstrnt-report-result -o tcg.log tcg PASS
else
    rstrnt-report-result -o tcg.log tcg FAIL
fi

echo "Test finished"
