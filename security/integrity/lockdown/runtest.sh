#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../kernel-include/runtest.sh || exit 1
. ../../../cmdline_helper/libcmd.sh || exit 1

function get_lockdown_status()
{
	echo $(cat /sys/kernel/security/lockdown | awk -F] '{print $1}' | awk -F[ '{print $2}');
}

rlJournalStart
	reboot=False
	if [ "${REBOOTCOUNT}" -eq 0 ]; then
		rlPhaseStartSetup "Check lockdown status, set to 'integrity'."
		rlShowRunningKernel
		devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
		pkg_mgr=$(K_GetPkgMgr)
		rlLog "pkg_mgr = ${pkg_mgr}"
		if [[ $pkg_mgr == "rpm-ostree" ]]; then
			export pkg_mgr_inst_string="-A -y --idempotent --allow-inactive install"
		else
			export pkg_mgr_inst_string="-y install"
		fi
		${pkg_mgr} ${pkg_mgr_inst_string} ${devel_pkg}
		# Check current lockdown state
		# set to 'integrity' if not already set.
		lockdown_status=$(get_lockdown_status)
		if [[ ${lockdown_status} != "integrity" ]]; then
			rlLog "Lockdown status is set to '${lockdown_status}', setting to 'integrity'."
			rlRun "change_cmdline 'lockdown=integrity'" || rlFail "Couldn't set lockdown."
			reboot=True
		else
			rlLog "Lockdown status is already set to 'integrity'."
			REBOOTCOUNT=1
		fi
		rlPhaseEnd
		if [ $reboot ]; then
			rlRun "rstrnt-reboot"
		fi
	fi
	if [ "${REBOOTCOUNT}" -eq 1 ]; then
		rlPhaseStartTest "Ensure that lockdown status cannot be changed at runtime."
			# Ensure input is available before continuing.
			if [ -d /dev/input ]; then
				# Clone external repository with unlockdown script.
				rlRun "git clone https://github.com/xairy/unlockdown.git"
				rlRun "pushd unlockdown/02-evdev"
				# Install package dependency.
				python_pkg="python3-evdev"
				if ! rpm -qa | grep ${python_pkg} >/dev/null; then
					rlLog "Installing python3-evdev package."
					${pkg_mgr} ${pkg_mgr_inst_string} ${python_pkg}
				fi
				# Execute script to send Alt+SysRq+x key clicks to console.
				# Key clicks can change lockdown status at runtime.
				rlRun "python evdev-sysrq.py" 0,255
				if [ $? -eq 0 ]; then
					rlLog "Alt+SysRq+x key clicks submitted, checking lockdown status."
					if [[ $(get_lockdown_status) = "none" ]]; then
						rlFail "Lockdown status was changed through Alt+SysRq+x."
					fi
				else
					rlLog "Alt+SysRq+x key clicks were not submitted. Skipping lockdown status check."
				fi
				rlRun "popd"
			else
				rlLog "No /dev/input available, skipping check."
			fi
		rlPhaseEnd
		rlPhaseStartTest "Ensure that lockdown mode prevents the loading of an unsigned kernel module."
			rlRun "pushd src"
			rlRun "make all"
			# Unsigned module test
			rlRun "make test"
			rlAssertGrep "Lockdown: insmod: unsigned module loading is restricted" dmesg-unsigned.log
			rlFileSubmit dmesg-unsigned.log
			rlRun "popd"
		rlPhaseEnd
	fi
	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
