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
		# # set to 'integrity' if not already set.
		lockdown_status=$(get_lockdown_status)
		if [[ ${lockdown_status} != "integrity" ]]; then
			rlLog "Lockdown status is set to '${lockdown_status}', setting to 'integrity'."
			rlRun "change_cmdline 'lockdown=integrity'" || exit 1
			rlRun "rstrnt-reboot"
		else
			rlLog "Lockdown status is already set to 'integrity'."
			REBOOTCOUNT=1
		fi
		rlPhaseEnd
	fi
	if [ "${REBOOTCOUNT}" -eq 1 ]; then
		rlPhaseStartTest "Ensure that lockdown status cannot be changed at runtime."
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
		rlRun "python evdev-sysrq.py" 0-255
		if [ $? -eq 0 ]; then
			rlLog "Alt+SysRq+x key clicks submitted, checking lockdown status."
			if [[ $(get_lockdown_status) = "none" ]]; then
				rlLog "Lockdown status was changed through Alt+SysRq+x."
				exit 1
			fi
		else
			rlLog "Alt+SysRq+x key clicks were not submitted. Skipping lockdown status check."
		fi
		rlRun "popd"
		rlPhaseEnd
		rlPhaseStartTest "Ensure SELinux prevents the loading of an unsigned kernel module."
			selinux_orig_state=$(getenforce)
			rlRun "echo ${selinux_orig_state} > selinux_orig_state"
			rlLog "selinux_orig_state: ${selinux_orig_state}"
			rlRun "pushd src"
			rlRun "make all"
			if [ ${selinux_orig_state} != "Disabled" ]; then
				# Unsigned module test
				rlRun "make test"
				rlAssertGrep "audit.*.avc:  denied  { module_load }.*.comm=\"insmod\".*.hw.ko" dmesg-unsigned.log -E
				rlRun "sed -i s/SELINUX=enforcing/SELINUX=disabled/g /etc/selinux/config"
				rlRun "popd"
				rlRun "touch selinux_state_changed"
				rlRun "rstrnt-reboot"
			else
				rlLog "SELinux was disabled, skipping check."
				rlRun "popd"
				REBOOTCOUNT=2
			fi
		rlPhaseEnd
	fi
	if [ "${REBOOTCOUNT}" -eq 2 ]; then
		rlPhaseStartTest "Ensure that lockdown mode prevents the loading of an unsigned kernel module."
			if [ $(getenforce) = "Disabled" ]; then
				rlRun "pushd src"
				# Unsigned module test
				rlRun "make test"
				rlAssertGrep "Lockdown: insmod: unsigned module loading is restricted" dmesg-unsigned.log
				rlFileSubmit dmesg-unsigned.log
				rlRun "popd"
			else
				rlLog "SELinux was not disabled."
				exit 1
			fi
		rlPhaseEnd
	fi
	rlPhaseStartCleanup
		if [ $(ls selinux_state_changed 2>/dev/null) ]; then
			selinux_current_state=$(getenforce)
			selinux_orig_state=$(cat selinux_orig_state)
			rlLog "selinux_orig_state: ${selinux_orig_state} , selinux_current_state: ${selinux_current_state}"
			if [ ${selinux_current_state} = ${selinux_orig_state} ]; then
				rlLog "SELinux current state is the same as the original state."
				exit 1
			fi
			rlRun "rm -f selinux_state_changed"
			rlRun "rm -f selinux_orig_state"
			regexp=$(echo ${selinux_current_state} | tr '[:upper:]' '[:lower:]')
			replacement=$(echo ${selinux_orig_state} | tr '[:upper:]' '[:lower:]')
			rlRun "sed -i s/SELINUX=${regexp}/SELINUX=${replacement}/g /etc/selinux/config"
			rlRun "rstrnt-reboot"
		fi
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
