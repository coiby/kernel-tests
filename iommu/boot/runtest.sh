#!/bin/bash
# vim: dict=/usr/share/rhts-library/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/iommu/boot
#   Description: Test various IOMMU boot options
#   Author: William Gomeringer <wgomerin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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

# Include libraries
. ../../cki_lib/libcki.sh || exit 1

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../kernel-include/runtest.sh || exit 1

TEST="iommu/boot/"
# file to write custom boot options (from CMDLINEARGS)
CustomBootOptions=custom-boot-options.txt
# file to use if no custom boot options passed
DefaultBootOptionsIntel=boot-options-intel.txt
DefaultBootOptionsAMD=boot-options-amd.txt
DefaultBootOptionsARM=boot-options-arm.txt
# file to store current boot options being tested
CurrentBootOptions=current-boot-options.txt
cpuvendor=$(lscpu | grep "^Vendor ID" | awk '{print $NF}')
dmesgErrors=iommu-dmesg-errors.txt
dmesgReport=iommu-dmesg-report.txt

function add_aboot_param ()
{
	CMDLINEARGS=$1

	current_aboot_cmdline=$(abootimg -i /boot/aboot-"${K_VER}"-"${K_REL}"."$(arch)".img | awk  '/cmdline/ {print}' | cut -f 4-"$NR" -d ' ')
	if [ -n "${current_aboot_cmdline}" ]; then
		current_aboot_cmdline+=" "
		current_aboot_cmdline+="${CMDLINEARGS}"
	else
		current_aboot_cmdline+="${CMDLINEARGS}"
	fi
	abootimg -u /boot/aboot-${K_VER}-${K_REL}.$(arch).img -c cmdline='${current_aboot_cmdline}'
	dd if=/boot/aboot-${K_VER}-${K_REL}.$(arch).img of=/dev/disk/by-partlabel/boot_a
	sync
}

function remove_aboot_param ()
{
	CMDLINEARGS=$1

	# shellcheck disable=SC2207
	current_aboot_cmdline=($(abootimg -i /boot/aboot-"${K_VER}"-"${K_REL}"."$(arch)".img | awk  '/cmdline/ {print}' | cut -f 4-"$NR" -d ' '))
	if [ -z "${current_aboot_cmdline[0]}" ]; then
		echo "Unable to find parameter in the allowed list."
		rstrnt-report-result "${TEST}" "FAIL" 0
		exit 0
	else
		for i in "${!current_aboot_cmdline[@]}"; do
			if echo "${CMDLINEARGS##-}" | grep -q "${current_aboot_cmdline[${i}]}"; then
				unset "current_aboot_cmdline[${i}]"
			fi
		done
		# want to keep spaces as delimiter
		# shellcheck disable=SC2124
		new_aboot_cmdline="${current_aboot_cmdline[@]}"
		abootimg -u /boot/aboot-${K_VER}-${K_REL}.$(arch).img -c cmdline="${new_aboot_cmdline}"
		dd if=/boot/aboot-${K_VER}-${K_REL}.$(arch).img of=/dev/disk/by-partlabel/boot_a
		sync
	fi
}

function change_cmdline ()
{
	CMDLINEARGS=$1

	# Update the boot loader.
	default=$(/sbin/grubby --default-kernel)

	# If the first character is - in the arguments, we remove them from
	# the kernel commandline.
	if echo "${CMDLINEARGS}" | grep -q "^-"; then
		echo "Cmdline to be removed: ${CMDLINEARGS##-}"
		if [ -e /sys/devices/soc0/machine ]; then
			remove_aboot_param ${CMDLINEARGS}
		elif [ -e /run/ostree-booted ]; then
			rpm-ostree kargs --delete-if-present="${CMDLINEARGS##-}" --import-proc-cmdline
		else
			/sbin/grubby --remove-args="${CMDLINEARGS##-}" --update-kernel="${default}"
		fi
	else
		echo "Cmdline to be added: ${CMDLINEARGS}"
		if [ -e /sys/devices/soc0/machine ]; then
			add_aboot_param ${CMDLINEARGS}
		elif [ -e /run/ostree-booted ]; then
			rpm-ostree kargs --append-if-missing="${CMDLINEARGS##-}" --import-proc-cmdline
		else
			/sbin/grubby --args="${CMDLINEARGS}" --update-kernel="${default}"
		fi
	fi

	# Once more change to s390 and s390x.
	if [ "$(arch)" = "s390" ] || [ "$(arch)" = "s390x" ]; then
		/sbin/zipl
	fi
}

function bootOptions() {
	bootOptionsFile=$1

	while read -r line; do
	# Check to see if new options have been set yet
		if [[ -z "${RSTRNT_REBOOTCOUNT}" ||  "${RSTRNT_REBOOTCOUNT}" -eq 0 ]] || \
			[[ ! -a $CurrentBootOptions ]]; then
			echo "Start test." | tee -a "${OUTPUTFILE}"
			echo "Old cmdline: $(cat /proc/cmdline)" | tee -a "${OUTPUTFILE}"

			change_cmdline "$line"
			code=$?

			if [ ${code} -ne 0 ]; then
				echo "Fail: error changing boot loader." |
				tee -a "${OUTPUTFILE}"
				rstrnt-report-result "${TEST}/boot_loader" "FAIL" 0
			else
				echo "${line}" > $CurrentBootOptions
				echo "Reboot now!" | tee -a "${OUTPUTFILE}"
				rstrnt-report-result "${TEST}/boot_loader" "PASS" 0
				rstrnt-reboot
				# Make sure the script doesn't continue if rstrnt-reboot get's killed
				# https://github.com/beaker-project/restraint/issues/219
				exit 0
			fi
		else
			# The reboot has finished. Verify the cmdline.
			echo "New cmdline: $(cat /proc/cmdline)" | tee -a "${OUTPUTFILE}"

			grep "$(cat $CurrentBootOptions)" /proc/cmdline
			code=$?
			# remove spaces for reporting boot option to beaker
			CurrentBootOptionsReport=$(cat $CurrentBootOptions | sed 's/\ /-/')

			if [ ${code} -ne 0 ]; then
				echo "Fail: error booting kernel with specified cmdline" |
				tee -a "${OUTPUTFILE}"
				rstrnt-report-result "${TEST}/$CurrentBootOptionsReport" "FAIL" 0
			else
				echo "boot options persisted through reboot." | tee -a "${OUTPUTFILE}"
				rstrnt-report-result "${TEST}/$CurrentBootOptionsReport" "PASS" 0
			fi
			rm $CurrentBootOptions
			change_cmdline "-${line}"
			sed -i "/$line\$/d" $bootOptionsFile
		fi
	done < $bootOptionsFile
}

function dmesgErrors() {
	dmesgLineNumber=0

	# find any iommu errors in dmesg/messages file
	while read -r dmesgLine; do
		dmesgLineNumber=$(($dmesgLineNumber+1))
		journalctl | grep "$dmesgLine"
		code=$?
		if [ ${code} -ne 1 ]; then
			echo "Fail: the following iommu regex matched in dmesg:" |
			tee -a "${OUTPUTFILE}"
			echo "$dmesgLine" | tee -a "${OUTPUTFILE}"
			echo "see TESTOUT.log for actual message or $dmesgReport for report" |
			tee -a "${OUTPUTFILE}"
			echo "$dmesgLineNumber FAIL $dmesgLine" >> $dmesgReport
		else
			echo "$dmesgLineNumber PASS $dmesgLine" >> $dmesgReport
		fi
	done < $dmesgErrors

	# report pass/fail to beaker if errors were found, upload report
	grep FAIL $dmesgReport
	dmesgReportCode=$?

	if [ ${dmesgReportCode} -ne 1 ]; then
		rstrnt-report-result "${TEST}/iommu-dmesg" "FAIL" 0
	else
		rstrnt-report-result "${TEST}/iommu-dmesg" "PASS" 0
	fi

	rstrnt-report-log -l $dmesgReport

}

function cleanupTest() {
	rm $dmesgReport
}

if [[ -n $CMDLINEARGS ]]; then
	if [ -z "${RSTRNT_REBOOTCOUNT}" ] || [ "${RSTRNT_REBOOTCOUNT}" -eq 0 ]; then
		IFS=':'
		for i in $CMDLINEARGS; do
			echo $i >> $CustomBootOptions
		done
	fi
	bootOptions $CustomBootOptions
	dmesgErrors
else
	if [[ $cpuvendor = "GenuineIntel" ]]; then
		bootOptions $DefaultBootOptionsIntel
		dmesgErrors
	elif [[ $cpuvendor =~ "ARM" || $cpuvendor =~ "Cavium" || $cpuvendor =~ "FUJITSU" ]]; then
		bootOptions $DefaultBootOptionsARM
		dmesgErrors
	elif [[ $cpuvendor = "AuthenticAMD" ]]; then
		bootOptions $DefaultBootOptionsAMD
		dmesgErrors
	else
		rstrnt-report-result "${TEST}/nonAMDorARMorIntelProcessor" "SKIP" 0
		exit 0
	fi
fi

cleanupTest
