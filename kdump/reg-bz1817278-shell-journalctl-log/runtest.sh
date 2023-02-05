#!/bin/sh

# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#  Author: Ruowen Qin   <ruqin@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1817278 - journalctl does not work in kdump shell
# Fixed in RHEL-8.4 kexec-tools-2.0.20-35
CheckSkipTest kexec-tools 2.0.20-35 && Report

ConfigScript() {
	rpm -q --quiet sysstat || InstallPackages sysstat
	RESTART_KDUMP=false
	ConfigAny "extra_bins /usr/bin/pidstat /usr/bin/vmstat"
	ConfigAny "extra_modules tun vfat"
	ConfigAny "kdump_pre /bin/kdump-pre.sh"
	ConfigAny "kdump_post /bin/kdump-post.sh"
	RhtsSubmit ${KDUMP_CONFIG}
	RhtsSubmit ${KDUMP_SYS_CONFIG}
	RhtsSubmit "/bin/kdump-pre.sh"
	RhtsSubmit "/bin/kdump-post.sh"

	RestartKdump
}

TestValidation() {
	Log "Validating output of kdump scripts"
	LogRun "ls -la /root/kdump-*.stamp"

	if [ ! -f /root/kdump-pre.stamp ] || [ ! -f /root/kdump-post.stamp ]; then
		MajorError "No kdump-{pre,post}.stamp generated in /root as exepcted"
	fi

	local str="No journal files were found"
	for file in /root/kdump-*.stamp; do
		RhtsSubmit "${file}"
		grep -i -q "${str}" "${file}" && {
			Error "journalctl output validation failed. "
			Error "It should not contain \"${str}\" in ${file}"
		}
	done

	str="Journal started"
	for file in /root/kdump-*.stamp; do
		RhtsSubmit "${file}"
		grep -i -q "${str}" "${file}" || {
			Error "journalctl output validation failed."
			Error "It should have \"${str}\" in ${file}"
		}
	done

}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC ConfigScript TestValidation
