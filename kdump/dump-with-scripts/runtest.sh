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

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1786220/1850874 - kexec-tools feature to Support /etc/kdump/{pre.d,post.d} interface to set up
#               multiple binary and script files
# Added in RHEL-8.3 kexec-tools-2.0.20-34.el8

CheckSkipTest kexec-tools 2.0.20-34 && Report

# Kdump support on kdump/post.d and pre.d directory is added on RHEL-8.3
ConfigScript()
{
	rpm -q --quiet sysstat || InstallPackages sysstat
	RESTART_KDUMP=false
	ConfigAny "extra_bins /usr/bin/pidstat /usr/bin/vmstat"
	ConfigAny "extra_modules tun vfat"
	ConfigAny "kdump_pre /bin/kdump-pre.sh"
	ConfigAny "kdump_post /bin/kdump-post.sh"
	RhtsSubmit ${KDUMP_CONFIG}
	RhtsSubmit ${KDUMP_SYS_CONFIG}

	for i in pre post; do
		rm -f /etc/kdump/${i}.d/*
		cp -f kdump-${i}_d*.sh /etc/kdump/${i}.d/
		[ -f /root/kdump-${i}_d.stamp ] && rm -f /root/kdump-${i}_d.stamp
	done
	RestartKdump
}

TestValidation()
{
	Log "Validating output of kdump scripts"
	LogRun "ls -la /root/kdump-*.stamp"
	for file in /root/kdump-*.stamp; do
		RhtsSubmit "${file}"
	done
	if [ ! -f /root/kdump-pre.stamp ] || [ ! -f /root/kdump-post.stamp ]; then
		Error "No kdump-{pre,post}.stamp generated in /root as exepcted"
	else
		grep -i -q memory /root/kdump-post.stamp || {
			Error "Script output validation failed. Failed to get 'memory' from kdump-post.stamp"
		}
	fi

	if [ ! -f /root/kdump-pre_d.stamp ] && [ ! -f /root/kdump-post_d.stamp ]; then
		Error "No kdump-{pre_d,post_d}.stamp generated in /root as exepcted"
	else
		for scriptdir in pre_d post_d; do
			str="kdump-${scriptdir}_1.sh executed;kdump-${scriptdir}_2.sh executed;"

			grep -q "${str}" \
				/root/kdump-${scriptdir}.stamp|| {
					Error "Script output validation failed on /root/kdump-${scriptdir}.stamp."
					Log "Expected: '${str}'"
					Log "Actual: $(cat /root/kdump-${scriptdir}.stamp)"
			}
		done
	fi
}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC ConfigScript TestValidation
