#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


# Source kdump common functions
. ../../cki_lib/libcki.sh || exit 1
. ../include/runtest.sh

TEST="/kdump/kexec-load"

KEXEC_VER=${KEXEC_VER:-"$(uname -r)"}

# From RHEL-9.3, kexec uses "-a" as default option. So here specifying
# "-c" to test kexec_load() call explicitly.
# Note, kexec 2.0.15 used in RHEL-7 doesn't support "-c" explicitly.

if $IS_RHEL && [ "${RELEASE}" -le 7 ]; then
    EXTRA_KEXEC_OPTIONS=${EXTRA_KEXEC_OPTIONS:-"-d"}
else
    EXTRA_KEXEC_OPTIONS=${EXTRA_KEXEC_OPTIONS:-"-d -c"}
fi

RunTest "KexecBoot kexecbootoption"
