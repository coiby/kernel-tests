#!/bin/bash
## -*- mode: Shell-script; sh-shell: bash; sh-basic-offset: 4; sh-indentation: 4; coding: utf-8-unix; indent-tabs-mode: t; ruler-mode-show-tab-stops: t; tab-width: 4 -*-
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Copyright (c) 2024 Red Hat, Inc
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary: Helper code for testing with IOMMUs
#
# Author: Jerry Snitselaar <jsnitsel@redhat.com>
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Required environment variables:
#
# DMA_MODNAME - name of driver being tested
# DMA_TESTNAME - name of test when logging or reporting results
# DMA_IOMMU_CONF - configuration to test

if test -z "${DMA_MODNAME}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "requires environment variable DMA_MODNAME to be set"
fi

if test -z "${DMA_TESTNAME}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "requires environment variable DMA_TESTNAME to be set"
fi

if test -z "${DMA_IOMMU_CONF}"; then
	test_complete "${DMA_TESTNAME}" "SKIP" "requires environment variable DMA_IOMMU_CONF to be set"
fi

if test -z "${DMA_STATEDIR}"; then
	DMA_STATEDIR="/mnt/testarea/.${DMA_MODNAME}"
fi

if ! test -z "${IOMMU_DEBUG}"; then
	set -x
fi

declare -A config_reboots
declare -A next_configs
declare -A next_config_phases

config_reboots=(
	["noiommu"]="0"
	["lazy"]="1"
	["sm-on-lazy"]="1"
	["strict"]="2"
	["sm-on-strict"]="2"
	["pt"]="3"
	["sm-on-pt"]="3"
	["sm-off-lazy"]="4"
	["sm-off-strict"]="5"
	["sm-off-pt"]="6"
)

next_configs=(
	["lazy"]="strict"
	["strict"]="pt"
	["pt"]="complete"
	["sm-on-lazy"]="sm-on-strict"
	["sm-on-strict"]="sm-on-pt"
	["sm-on-pt"]="sm-off-lazy"
	["sm-off-lazy"]="sm-off-strict"
	["sm-off-strict"]="sm-off-pt"
	["sm-off-pt"]="complete"
	["noiommu"]="complete"
)

next_config_phases=(
	["lazy"]="config"
	["strict"]="config"
	["pt"]="cleanup"
	["sm-on-lazy"]="config"
	["sm-on-strict"]="config"
	["sm-on-pt"]="config"
	["sm-off-lazy"]="config"
	["sm-off-strict"]="config"
	["sm-off-pt"]="cleanup"
	["noiommu"]="cleanup"
)

iommu_debug ()
{
	if ! test -z "${IOMMU_DEBUG}"; then
		echo "${DMA_TESTNAME} ${1} at ${2}: ${3}"
	fi
}

ats_fail_check ()
{
	if journalctl -k | grep -q "DMAR:.*PCE for translation request specifies blocking"; then
		return 0
	fi

	return 1
}

check_dma_faults ()
{
	if check_config "noiommu"; then
		return
	fi

	case "$(uname -m)" in
		"x86_64")
			if is_vendor "intel"; then
				check_dmar_faults "${1}-check-dma-faults"
			elif is_vendor "amd"; then
				check_amd_dma_faults "${1}-check-dma-faults"
			fi
			;;
		"aarch64")
			check_smmu_faults "${1}-check-dma-faults"
			;;
		*)
			;;
	esac
}

SMMU_V3_FAULTS=(
	"arm-smmu-v3.* Unexpected global error reported"
	"arm-smmu-v3.* (MSI|PRIQ|EVTQ) write aborted"
	"arm-smmu-v3.* (PRIQ|EVTQ) overflow detected -- (events|requests) lost"
	"arm-smmu-v3.* failed to allocate l2 stream table for SID"
	"arm-smmu-v3.* failed to allocate l1 stream table"
	"arm-smmu-v3.* failed to allocate linear stream table"
	"arm-smmu-v3.* failed to disable irqs"
	"arm-smmu-v3.* GBPA not responding to update"
	"arm-smmu-v3.* CMD_SYNC timeout at"
	"arm-smmu-v3.* failed to clear "
	"arm-smmu-v3.* CMDQ error .*: (Illegal command|Abort on command fetch|ATC invalidate timeout)"
	".*Failed to enable ATS \(STU"
	".*Failed to enable PASID"
	".*cannot attach - SVA enabled"
	"arm-smmu-v3.* failed to allocate queue.* for (cmdq|evtq|priq)"
	"arm-smmu-v3.* MMIO region too small"
	"arm-smmu-v3.* RMR SID.* bypass failed"
	"arm-smmu-v3.* cannot disable SVA"
	"arm-smmu-v3.* CMDQ timeout"
)

SMMU_V2_FAULTS=(
	"arm-smmu.*Unexpected global fault, this could be serious"
	"arm-smmu.*Blocked unknown Stream ID"
)

check_smmu_faults ()
{

	declare -i ret=0

	mapfile DMESG < <(dmesg)
	if is_arm_smmu_v3; then
		# global fault check
		if dmesg | grep -q "device has entered Service Failure Mode"; then
			test_complete "${1}" "FAIL" "Service Failure Mode event detected"
		fi
		if grep -qE -f <(printf "%s\n" "${SMMU_V3_FAULTS[@]}") < <(printf "%s\n" "${DMESG[@]}"); then
			ret+=1
			echo "${1} arm-smmu-v3 error message found"
		fi
		repat="arm-smmu-v3.* event (0x[0-9a-f]{2}) received"
		mapfile EVENTS < <(grep -iP "arm-smmu-v3.*event (0x[0-9a-f]{2}) received" < <(printf "%s\n" "${DMESG[@]}"))
		for l in "${EVENTS[@]}";
		do
			if [[ ${l} =~ ${repat} ]]; then
				evt_id="${BASH_REMATCH[1]}"
				case "${evt_id}" in
					"0x10")
						echo "${1} translation fault detected"
						ret+=1
						;;
					"0x11")
						echo "${1} address size fault detected"
						ret+=1
						;;
					"0x12")
						echo "${1} access fault detected"
						ret+=1
						;;
					"0x13")
						echo "${1} permission fault detected"
						ret+=1
						;;
					*)
						;;
				esac
			fi
		done
	else
		if dmesg | grep -qE -f <(printf "%s\n" "${SMMU_V2_FAULTS[@]}") < <(printf "%s\n" "${DMESG[@]}"); then
			ret+=1
			echo "${1} arm-smmu error message found"
		fi
		# Context fault
		mapfile EVENTS < <(grep -i "Unhandled context fault" < <(printf "%s\n" "${DMESG[@]}"))
		# fsr, iova, fsynr, cbfsynra, cb
		ctx_repat="Unhandled context fault: fsr=(0x[0-9a-f]{4,16}), iova=(0x[0-9a-f]{4,16}) fsynr=(0x[0-9a-f]{4,16}) cbfsynra=(0x[0-9a-f]{4,16}) cb=([0-9]+)$"
		for l in "${EVENTS[@]}";
		do
			if [[ ${l} =~ ${ctx_repat} ]]; then
				echo "${1} Found an unhandled context fault"
				ret+=1
				echo "${1} FSR: ${BASH_REMATCH[1]}"
				echo "${1} IOVA: ${BASH_REMATCH[2]}"
				echo "${1} FSYNR: ${BASH_REMATCH[3]}"
				echo "${1} CBFSYNRA: ${BASH_REMATCH[4]}"
				echo "${1} CB: ${BASH_REMATCH[5]}"
			fi
		done
	fi

	if test "$ret" -eq 0; then
		test_continue "${1}" "PASS" "no smmu transaction faults found"
	else
		test_continue "${1}" "FAIL" "smmu transaction faults found"
	fi
}

AMD_IOMMU_FAULTS=(
	"Event logged \[IO_PAGE_FAULT"
	"Event logged \[Device not attached to domain properly\]"
	"Event logged \[RMP_PAGE_FAULT"
	"Event logged \[ILLEGAL_DEV_TABLE_ENTRY"
	"Event logged \[ILLEGAL_COMMAND_ERROR"
	"Event logged \[IOTLB_INV_TIMEOUT"
	"Event logged \[INVALID_DEVICE_REQUEST"
	"Event logged \[INVALID_PPR_REQUEST"
	"Event logged \[UNKNOWN event"
	"Event logged \[COMMAND_HARDWARE_ERROR"
	"Event logged \[RMP_HW_ERROR"
	"Event logged \[DEV_TAB_HARDWARE_ERROR"
	"Event logged \[PAGE_TAB_HARDWARE_ERROR"
)

check_amd_dma_faults ()
{
	if ! test "$(uname -m)" = "x86_64"; then
		return
	fi

	declare -i ret=0
	eventre="Event logged \[([a-zA-Z_]+) "

	mapfile DMESG < <(dmesg)
	mapfile EVENTS < <(grep -i -f <(printf "%s\n" "${AMD_IOMMU_FAULTS[@]}") < <(printf "%s\n" "${DMESG[@]}"))
	for l in "${EVENTS[@]}";
	do
		if [[ ${l} =~ ${eventre} ]]; then
			echo "${1} Found an IOMMU fault event."
			ret+=1

			event="${BASH_REMATCH[1]}"
			sbdf=""
			domain=""
			address=""
			gpa=""
			spa=""
			vmg_tag=""
			flags_rmp=""
			flags=""
			pasid=""
			tag=""

			case "${event}" in
				"IO_PAGE_FAULT")
					# sbdf , seg, domain, address, flags
					repat=".+(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]).* domain=(0x[0-9a-f]{4}) address=(0x[0-9a-f]{4,16}) flags=(0x[0-9a-f]{4})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						domain="${BASH_REMATCH[3]}"
						address="${BASH_REMATCH[4]}"
						flags="${BASH_REMATCH[5]}"
					fi
					;;
				"RMP_PAGE_FAULT" )
					# sbdf, seg, vmg_tag,  gpa, flags_rmp, flags
					repat=".+(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]).* vmg_tag=(0x[0-9a-f]{4}), gpa=(0x[0-9a-f]{4,16}), flags_rmp=(0x[0-9a-f]{4}), flags=(0x[0-9a-f]{4})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						vmg_tag="${BASH_REMATCH[3]}"
						gpa="${BASH_REMATCH[4]}"
						flags_rmp="${BASH_REMATCH[5]}"
						flags="${BASH_REMATCH[6]}"
					fi
					;;
				"RMP_HW_ERROR" )
					# sbdf, seg, vmg_tag, spa, flags
					repat=".+(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]).* vmg_tag=(0x[0-9a-f]{4}), spa=(0x[0-9a-f]{4,16}), flags=(0x[0-9a-f]{4})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						vmg_tag="${BASH_REMATCH[3]}"
						spa="${BASH_REMATCH[4]}"
						flags="${BASH_REMATCH[5]}"
					fi
					;;
				"PAGE_TAB_HARDWARE_ERROR" )
					# sbdf, seg, pasid, address, flags
					repat=".* device=(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]) pasid=(0x[0-9a-f]{5}) address=(0x[0-9a-f]{4,16}) flags=(0x[0-9a-f]{4})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						pasid="${BASH_REMATCH[3]}"
						address="${BASH_REMATCH[4]}"
						flags="${BASH_REMATCH[5]}"
					fi
					;;
				"DEV_TAB_HARDWARE_ERROR" )
					# sbdf, seg, address, flags
					repat=".+ device=(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]) address=(0x[0-9a-f]{4,16}) flags=(0x[0-9a-f]{4})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						address="${BASH_REMATCH[3]}"
						flags="${BASH_REMATCH[4]}"
					fi
					;;
				"INVALID_PPR_REQUEST" )
					# sbdf, seg, pasid, address, flags, tag
					repat=".* device=(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]) pasid=(0x[0-9a-f]{5}) address=(0x[0-9a-f]{4,16}) flags=(0x[0-9a-f]{4}) tag=(0x[0-9a-f]{3})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						pasid="${BASH_REMATCH[3]}"
						address="${BASH_REMATCH[4]}"
						flags="${BASH_REMATCH[5]}"
						tag="${BASH_REMATCH[6]}"
					fi
					;;
				"INVALID_DEVICE_REQUEST" )
					# sbdf, seg, pasid, address, flags
					repat=".* device=(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]) pasid=(0x[0-9a-f]{5}) address=(0x[0-9a-f]{4,16}) flags=(0x[0-9a-f]{4})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						pasid="${BASH_REMATCH[3]}"
						address="${BASH_REMATCH[4]}"
						flags="${BASH_REMATCH[5]}"
					fi
					;;
				"IOTLB_INV_TIMEOUT" )
					# sbdf, seg, address
					repat=".+ device=(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]) address=(0x[0-9a-f]{4,16})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						address="${BASH_REMATCH[3]}"
					fi
					;;
				"ILLEGAL_COMMAND_ERROR" )
					# address
					repat=".+ address=(0x[0-9a-f]{4,16})\]"
					if [[ ${l} =~ ${repat} ]]; then
						address="${BASH_REMATCH[1]}"
					fi
					;;
				"COMMAND_HARDWARE_ERROR" )
					# address, flags
					repat=".+ address=(0x[0-9a-f]{4,16}) flags=(0x[0-9a-f]{4})\]"
					if [[ ${l} =~ ${repat} ]]; then
						address="${BASH_REMATCH[1]}"
						flags="${BASH_REMATCH[2]}"
					fi
					;;
				"ILLEGAL_DEV_TABLE_ENTRY" )
					# sbdf, pasid, address, flags
					repat=".* device=(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]) pasid=(0x[0-9a-f]{5}) address=(0x[0-9a-f]{4,16}) flags=(0x[0-9a-f]{4})\]"
					if [[ ${l} =~ ${repat} ]]; then
						sbdf="${BASH_REMATCH[1]}"
						pasid="${BASH_REMATCH[3]}"
						address="${BASH_REMATCH[3]}"
						flags="${BASH_REMATCH[4]}"
					fi
					;;
			esac

			if test "${event}" = "Device"; then
				echo "${1} Transaction faulted. Device not attached to domain properly. See dmesg.log"
				continue
			elif test "${event}" = "UNKNOWN"; then
				echo "${1} Transaction faulted. Unknown event occurred. See dmesg.log"
				continue
			fi

			echo "${1} Event: ${event}"
			if ! test -z "${sbdf}"; then
				sbdf="$(lspci -D -s ${sbdf} | awk '{print $1}')"
				modpci="$(lspci -k -s ${sbdf} | grep 'driver in use' | cut -d ' ' -f5)"
				echo "${1} Transaction faulted from pci device ${sbdf} driver: ${modpci}"
			fi

			if ! test -z "${domain}"; then
				echo "${1} domain: ${domain}"
			fi

			if ! test -z "${pasid}"; then
				echo "${1} pasid: ${pasid}"
			fi

			if ! test -z "${address}"; then
				echo "${1} address: ${address}"
			fi

			if ! test -z "${gpa}"; then
				echo "${1} gpa: ${gpa}"
			fi

			if ! test -z "${spa}"; then
				echo "${1} spa: ${spa}"
			fi

			if ! test -z "${vmg_tag}"; then
				echo "${1} vmg_tag: ${vmg_tag}"
			fi

			if ! test -z "${flags_rmp}"; then
				echo "${1} flags_rmp: ${flags_rmp}"
			fi

			if ! test -z "${flags}"; then
				echo "${1} flags: ${flags}"
			fi

			if ! test -z "${tag}"; then
				echo "${1} tag: ${tag}"
			fi

			if test "${event}" = "IO_PAGE_FAULT"; then
				bad_bios_check "${1}" "${address}"
			fi

			if ! test -z "${sbdf}"; then
				dump_iommu_group_info "${1}" "${sbdf}"
			fi
		fi
	done

	if test "$ret" -eq 0; then
		test_continue "${1}" "PASS" "no iommu transaction faults found"
	else
		test_continue "${1}" "FAIL" "iommu transaction faults found"
	fi
}

check_dmar_faults ()
{
	declare -i faults=0
	declare -i pte_set=0
	# 1 - pcibdf
	# 2 - pci seg, if exists (currently intel doesn't display the segment here, but this should future proof)
	# 3 - fault address
	# 4 - fault reason code
	# 5 - fault reason string
	repat="DMAR.*\] Request device \[(([0-9a-f]{4}:){0,1}[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]{1})\] fault addr (0x[0-9a-f]{4,16}) \[fault reason (0x[0-9a-f]{2})\] (.*)"

	# Trying to set PTE that is currently set
	repat_PTE_set="DMAR: ERROR: DMA PTE for vPFN 0x[0-9a-f]{5,13} already set"

	mapfile DMESG < <(dmesg)
	for l in "${DMESG[@]}";
	do
		if [[ ${l} =~ ${repat} ]]; then
			echo "${1} Found a DMAR fault:"
			faults+=1
			pcibdf="${BASH_REMATCH[1]}"
			sbdf="$(lspci -D -s ${pcibdf} | awk '{print $1}')"
			modpci="$(lspci -k -s ${sbdf} | grep 'driver in use' | cut -d ' ' -f5)"
			fault_addr="${BASH_REMATCH[3]}"
			fault_code="${BASH_REMATCH[4]}"
			fault_reason="${BASH_REMATCH[5]}"
			echo "${1} Transaction faulted from pci device ${sbdf} at address ${fault_addr} driver: ${modpci}"
			echo "${1} Fault reason (${fault_code}): ${fault_reason}"
			if ((0x0 <= fault_code)) && ((fault_code < 0x20)); then
				echo "${1} DMA Remapping Fault"
				bad_bios_check "${1}" "${fault_addr}"
			elif ((fault_code < 0x30)); then
				echo "${1} INTR Remapping Fault"
			elif ((fault_code < 0x91)); then
				echo "${1} Scalable Mode Fault"
			else
				echo "${1} Unknown Fault Code!"
			fi
			dump_iommu_group_info "${1}" "${sbdf}"
		elif [[ ${l} =~ ${repat_PTE_set} ]]; then
			echo "${l}"
			pte_set+=1
		fi
	done

	if test "${faults}" -eq 0 -a "${pte_set}" -eq 0; then
		test_continue "${1}" "PASS" "no iommu transaction faults found"
	else
		if test "${pte_set}" -ne 0; then
			test_continue "${1}" "FAIL" "attempted to set PTE that was already set"
		else
			test_continue "${1}" "FAIL" "iommu transaction faults found"
		fi
	fi
}

bad_bios_check ()
{
	local fault_addr="${2}"
	local re="(.* reserve setup_data: \[mem )((0x[0-9a-f]{16})-(0x[0-9a-f]{16}))(\] reserved)"

	mapfile DMESG < <(journalctl -k)
	mapfile RMR < <(grep "reserve setup_data:" <(printf "%s\n" "${DMESG[@]}"))
	for l in "${RMR[@]}";
	do
		if [[ ${l} =~ ${re} ]]; then
			low_addr="${BASH_REMATCH[3]}"
			high_addr="${BASH_REMATCH[4]}"

			if ((low_addr <= fault_addr)) && ((fault_addr <= high_addr)); then
				echo ""
				echo "${1}	 Fault address ${fault_addr} falls within the bios reserved range ${low_addr}-${high_addr}"
				echo "${1}	 This possibly is an issue with the acpi table presented by the bios"
				if is_vendor "intel"; then
					echo "${1}	 There might need to be an RMRR entry added to the DMAR table for the faulting device"
					dump_sys_fw_ver_info
				elif is_vendor "amd"; then
					echo "${1}	 There might need to be an IVMD entry added to the IVRS table for the faulting device"
					dump_sys_fw_ver_info
				fi
				echo ""
			fi
		fi
	done
}

dump_sys_fw_ver_info ()
{
	echo "${DMA_TESTNAME} $(uname -a)"
	mapfile BIOS < <(dmidecode -t 0)
	for l in "${BIOS[@]}";
	do
		echo -n "${DMA_TESTNAME} ${l}"
	done
}

dump_iommu_group_info ()
{
	iommu_group=""
	re="(.* ${sbdf}: Adding to iommu group )([0-9]+)"

	l=$(journalctl -k | grep "${2}" | grep "Adding to iommu group")
	if [[ ${l} =~ ${re} ]]; then
		iommu_group="${BASH_REMATCH[2]}"
	fi

	if ! test -z "${iommu_group}"; then
		echo ""
		echo "${1}	 IOMMU Group: ${iommu_group}"
		echo "${1}	   DMA Domain type: $(cat /sys/kernel/iommu_groups/${iommu_group}/type)"
		echo ""
		mapfile REGIONS < /sys/kernel/iommu_groups/${iommu_group}/reserved_regions
		echo "${1}	   Reserved Regions:"
		for l in "${REGIONS[@]}"; do
			echo "${1}		 ${l}"
		done
	fi
}

iommu_state_check ()
{
	case "$(uname -m)" in
		"x86_64")
			if is_vendor "intel"; then
				intel_iommu_state_check
			else
				amd_iommu_state_check
			fi
			;;
		"aarch64")
			arm_smmu_state_check
			;;
	esac
}

intel_iommu_state_check ()
{
	case "$(get_config)" in
		"sm-on-lazy")
			if ! is_intel_sm_enabled || ! batched_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"sm-on-strict")
			if ! is_intel_sm_enabled || ! strict_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"sm-on-pt")
			if ! is_intel_sm_enabled || ! passthrough_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"sm-off-lazy")
			if is_intel_sm_enabled || ! batched_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"sm-off-strict")
			if is_intel_sm_enabled || ! strict_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"sm-off-pt")
			if is_intel_sm_enabled || ! passthrough_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"lazy")
			if ! batched_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"strict")
			if ! strict_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"pt")
			if ! passthrough_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"forcedac")
			if ! is_forcedac_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"sp_off")
			if ! is_sp_off_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"igfx_off")
			if ! is_igfx_off_enabled; then
				test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		*)
			test_complete "${DMA_TESTNAME}-intel-iommu-state-check" "SKIP" "IOMMU configuration $(get_config) is not known"
			;;
	esac
}

amd_iommu_state_check ()
{
	case "$(get_config)" in
		"lazy")
			if ! batched_iotlb_invalidation_enabled; then
				if ! is_npcache_capable || ! npcache_strict_check; then
					test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
				fi
			fi
			;;
		"strict")
			if ! strict_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"pt")
			if ! passthrough_enabled; then
				test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"off")
			# should be supported disabled
			if amd_iommu_enabled; then
				test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"forcedac")
			if ! is_forcedac_enabled; then
				test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"force_enable")
			if is_stoney_ridge && ! amd_iommu_enabled; then
				test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"pgtbl_v1")
			if ! is_pgtbl_v1_enabled; then
				test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"pgtbl_v2-lazy")
			if ! is_pgtbl_v2_enabled || ! batched_iotlb_invalidation_enabled; then
				pgtbl_v2_cap_fail
				if ! is_npcache_capable || ! npcache_strict_check; then
					test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
				fi
			fi
			;;
		"pgtbl_v2-strict")
			if ! strict_iotlb_invalidation_enabled || ! is_pgtbl_v2_enabled; then
				pgtbl_v2_cap_fail
				test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"pgtbl_v2-pt")
			# this should fall back to v1 page tables
			if is_pgtbl_v2_enabled && ! passthrough_enabled && ! v2_passthrough_check; then
				pgtbl_v2_cap_fail
				test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		*)
			test_complete "${DMA_TESTNAME}-amd-iommu-state-check" "SKIP" "IOMMU configuration $(get_config) is not known"
			;;
	esac
}

arm_smmu_state_check ()
{
	case "$(get_config)" in
		"lazy")
			if ! batched_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-arm-smmu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"strict")
			if ! strict_iotlb_invalidation_enabled; then
				test_complete "${DMA_TESTNAME}-arm-smmu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"pt")
			if ! passthrough_enabled; then
				test_complete "${DMA_TESTNAME}-arm-smmu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		"forcedac")
			if ! is_forcedac_enabled; then
				test_complete "${DMA_TESTNAME}-arm-smmu-state-check" "FAIL" "IOMMU did not initialize in correct configuration"
			fi
			;;
		*)
			test_complete "${DMA_TESTNAME}-arm-smmu-state-check" "SKIP" "IOMMU configuration $(get_config) is not known"
			;;
	esac
}

iommu_supported_check ()
{
	case "$(uname -m)" in
		"x86_64")
			if is_vendor "intel"; then
				intel_iommu_supported
			else
				amd_iommu_supported
			fi
			;;
		"aarch64")
			arm_smmu_supported
			;;
	esac
}

iommu_enabled_check ()
{
	case "$(uname -m)" in
		"x86_64")
			if is_vendor "intel"; then
				if ! intel_iommu_enabled; then
					test_complete "${DMA_TESTNAME}-intel-iommu-enabled-check" "FAIL" "IOMMU didn't initialize"
				fi
			else
				if test "$(get_config)" != "off"; then
					if ! amd_iommu_enabled; then
						test_complete "${DMA_TESTNAME}-amd-iommu-enabled-check" "FAIL" "IOMMU didn't initialize"
					fi
				fi
			fi
			;;
		"aarch64")
			if ! arm_smmu_enabled; then
				test_complete "${DMA_TESTNAME}-arm-smmu-enabled-check" "FAIL" "SMMU didn't initialize"
			fi
			;;
		*)
			test_complete "${DMA_TESTNAME}-iommu-enabled-check" "SKIP" "$(uname -m) is not supported by this test"
			;;
	esac
}

passthrough_enabled ()
{
	if journalctl -k | grep -q "iommu: Default domain type: Passthrough"; then
		return 0
	fi

	return 1
}

translation_enabled ()
{
	if journalctl -k | grep -q "iommu: Default domain type: Translated"; then
		return 0
	fi

	return 1
}

strict_iotlb_invalidation_enabled ()
{
	if translation_enabled; then
		if journalctl -k | grep -q "DMA domain TLB invalidation policy: strict"; then
			return 0
		fi
	fi
	return 1
}

batched_iotlb_invalidation_enabled ()
{
	if translation_enabled; then
		if journalctl -k | grep -q "DMA domain TLB invalidation policy: lazy"; then
			return 0
		fi
	fi
	return 1
}

# ARM SMMU features
arm_smmu_supported ()
{
	if ! arm_smmu_bios_enabled; then
		test_complete "${DMA_TESTNAME}-arm-smmu-supported" "SKIP" "No IORT table presented by BIOS"
	fi
}

arm_smmu_iort_check ()
{
	# check for existence of iasl, then dump the IORT table
	# check for node types 03 or 04 or whichever is passed
	# by caller
	if ! test -f /sys/firmware/acpi/tables/IORT; then
		return 1
	fi

	cp /sys/firmware/acpi/tables/IORT /mnt/scratchspace/IORT.dat

	# don't waste time decompiling again if we already have done it
	if ! test -f /mnt/scratchspace/IORT.dsl; then
		iasl -d /mnt/scratchspace/IORT.dat
	fi

	if ! test -f /mnt/scratchspace/IORT.dsl; then
		echo "${DMA_TESTNAME}" "Failure in decompiling the IORT table"
		dump_sys_fw_ver_info
		return 1
	fi

	declare -i match_start=0
	declare -i match_end=0
	declare -i ret=1
	declare node_type=""
	declare node_revision=""
	declare mapping_count=""
	declare base_addr=""
	declare flags=""

	repat_type="Type : (0[34])"
	repat_rev="Revision : ([0-9A-F]{2})"
	repat_mapcnt="Mapping Count : ([0-9A-F]{8})"
	repat_baseaddr="Base Address : ([0-9A-F]{16})"
	repat_flags="Flags \(decoded below\) : ([0-9A-F]{8})"

	mapfile IORTINFO < <(grep -E -A2 "Signature :.+IORT" "/mnt/scratchspace/IORT.dsl")
	for l in "${IORTINFO[@]}";
	do
		if [[ ${l} =~ $repat_rev ]]; then
			iort_rev=$((16#${BASH_REMATCH[1]}))
		fi
	done

	mapfile IORTINFO < <(grep -E -A20 "$repat_type" "/mnt/scratchspace/IORT.dsl")
	for l in "${IORTINFO[@]}";
	do
		if [[ ${l} =~ $repat_type  ]]; then
			match_start=1
			node_type="${BASH_REMATCH[1]}"
		elif [[ ${l} =~ $repat_rev	]]; then
			node_revision="${BASH_REMATCH[1]}"
		elif [[ ${l} =~ $repat_mapcnt  ]]; then
			mapping_count="${BASH_REMATCH[1]}"
		elif [[ ${l} =~ $repat_baseaddr ]]; then
			base_addr=$((16#${BASH_REMATCH[1]}))
		elif [[ ${l} =~ $repat_flags ]]; then
			flags="${BASH_REMATCH[1]}"
			match_end=1
		fi

		# we've parsed a node for an smmu
		if test $match_start -eq 1 -a $match_end -eq 1; then

			# are we searching for a specific type and found one
			if ! test -z "${1}"; then
				if test "${1}" = "${node_type}"; then

					echo ""
					echo "${DMA_TESTNAME} Found Node Type: ${node_type}"
					echo ""
					echo "${DMA_TESTNAME} IORT Table Revision: ${iort_rev}"
					echo "${DMA_TESTNAME} Node Type: ${node_type}"
					echo "${DMA_TESTNAME} Revision: ${node_revision}"
					echo "${DMA_TESTNAME} Mapping Count: ${mapping_count}"
					echo "${DMA_TESTNAME} Base Address: " $(printf "0x%016x" "${base_addr}")
					echo "${DMA_TESTNAME} Flags: ${flags}"
					ret=0

					# simple sanity check on base address
					if ((base_addr == 0)); then
						echo "${DMA_TESTNAME} Base Address for node type ${node_type} is null!"
						dump_sys_fw_ver_info
					fi

					break
				fi
			else
				echo ""
				echo "${DMA_TESTNAME} IORT Table Revision: ${iort_rev}"
				echo "${DMA_TESTNAME} Node Type: ${node_type}"
				echo "${DMA_TESTNAME} Revision: ${node_revision}"
				echo "${DMA_TESTNAME} Mapping Count: ${mapping_count}"
				echo "${DMA_TESTNAME} Base Address: " $(printf "0x%016x" "${base_addr}")
				echo "${DMA_TESTNAME} Flags: ${flags}"

				ret=0

				# simple sanity check on base address
				if ((base_addr == 0)); then
					echo "${DMA_TESTNAME} Base Address for node type ${node_type} is null!"
					dump_sys_fw_ver_info
				fi
			fi

			# reset for another possible node match
			match_start=0
			match_end=0
			node_type=""
			node_revision=""
			mapping_count=""
			base_addr=""
			flags=""
		fi
	done

	return $ret
}

arm_smmu_bios_enabled ()
{
	if ! arm_smmu_iort_check; then
		return 1
	fi

	return 0
}

sysfs_iommu_count ()
{
	declare -i count

	count=$(find /sys/class/iommu -type l -regex "${1}" | wc -l)

	echo "${count}"
}

arm_smmu_enabled ()
{
	if arm_smmu_bios_enabled; then
		if is_arm_smmu_v3; then
			if test $(sysfs_iommu_count ".*/smmu3\.0x[0-9a-fA-F]+") = "0"; then
				return 1
			fi
		else
			if test $(sysfs_iommu_count ".*/smmu\.0x[0-9a-fA-F]+") = "0"; then
				return 1
			fi
		fi
	else
		return 1
	fi

	return 0
}

is_arm_smmu_v3 ()
{
	if ! arm_smmu_iort_check "04"; then
		return 1
	fi

	return 0
}

# AMD features
amd_iommu_supported ()
{
	if ! is_vendor "amd"; then
		test_complete "${DMA_TESTNAME}-amd-iommu-supported-check" "SKIP" "can only run on AMD platforms"
	fi

	if ! amd_iommu_bios_enabled; then
		test_complete "${DMA_TESTNAME}-amd-iommu-supported-check" "SKIP" "AMD-Vi is not enabled in the BIOS"
	fi
}

amd_iommu_bios_enabled ()
{
	if ! test -f /sys/firmware/acpi/tables/IVRS; then
		return 1
	fi

	return 0
}

amd_iommu_enabled ()
{
	if amd_iommu_bios_enabled; then
		if test $(sysfs_iommu_count ".*/ivhd[0-9]+") != "0"; then
			return 0
		elif journalctl -k | grep -qE "IOMMU[0-9]+: Failed to initalize IOMMU Hardware"; then
			return 1
		fi
	fi
	return 1
}

# Intel features
intel_iommu_bios_enabled ()
{
	if ! test -f /sys/firmware/acpi/tables/DMAR; then
		return 1
	fi

	return 0
}

npcache_strict_check ()
{
	if ! journalctl -k | grep -q "Using strict mode due to virtualization"; then
		return 1
	fi

	return 0
}

is_npcache_capable ()
{
	if test $(sysfs_iommu_count ".*/ivhd[0-9]+") = "0"; then
		echo "${DMA_TESTNAME} No IVHD devices in sysfs"
		return 1
	fi

	NPCACHE=$((1 << 26))

	# then check iommu cap see if register shows support
	for d in /sys/class/iommu/ivhd*; do
		if test $((16#$(cat "${d}/amd-iommu/cap") & NPCACHE)) -eq 0; then
			return 1
		fi
	done

	return 0
}

is_stoney_ridge ()
{
	if test $(($(lspci -d 1002:9e84 | wc -l))) -eq 0; then
		return 1
	fi

	return 0
}

is_pgtbl_v1_enabled ()
{
	if is_pgtbl_v2_enabled; then
		return 1
	fi

	return 0
}

v2_passthrough_check()
{
	if ! journalctl -k | grep -q "V2 page table doesn't support passthrough mode. Fallback to v1"; then
		return 1
	fi

	return 0
}

pgtbl_v2_cap_fail ()
{
	if journalctl -k | grep -q "Cannot enable v2 page table for DMA-API. Fallback to v1"; then
		test_complete "${DMA_TESTNAME}" "SKIP" "Platform doesn't have capabilities to support V2 page tables"
	fi
}

is_pgtbl_v2_enabled ()
{
	if ! journalctl -k | grep -qE "V2 page table enabled \(Paging mode : [1-6] level\)"; then
		return 1
	fi

	return 0
}

intel_iommu_supported ()
{
	if ! is_vendor "intel"; then
		test_complete "${DMA_TESTNAME}-intel-iommu-supported-check" "SKIP" "can only run on Intel Platforms"
	fi

	if ! intel_iommu_bios_enabled; then
		test_complete "${DMA_TESTNAME}-intel-iommu-supported-check" "SKIP" "VT-d is not enabled in BIOS"
	fi

	if [[ ${DMA_IOMMU_CONF} =~ "sm-on" ]] && ! is_intel_sm_supported; then
		test_complete "${DMA_TESTNAME}-intel-iommu-supported-check" "SKIP" "scalable mode is not supported on this system"
	fi
}

intel_iommu_enabled ()
{
	if intel_iommu_bios_enabled; then
		if test $(sysfs_iommu_count ".*/dmar[0-9]+") != "0"; then
			return 0
		fi
	fi
	return 1
}

is_igfx_off_enabled ()
{
	if ! journalctl -k | grep -q "Disable GFX device mapping"; then
		return 1
	fi

	return 0
}

is_sp_off_enabled ()
{
	if ! journalctl -k | grep -q "Disable supported super page"; then
		return 1
	fi

	return 0
}

is_forcedac_enabled ()
{
	# Check kernel log for forcing DAC message
	if ! journalctl -k | grep -q "Forcing DAC for PCI devices"; then
		return 1
	fi

	return 0
}

is_intel_feature_supported ()
{
	declare -i count=0

	if test $(sysfs_iommu_count ".*/dmar[0-9]+") = "0"; then
		echo "${DMA_TESTNAME} No DMAR devices in sysfs"
		return 1
	fi

	# then check dmar ecap see if register shows support
	for d in /sys/class/iommu/dmar*; do
		if test $((16#$(cat "${d}/intel-iommu/ecap") & $2)) -eq "${2}"; then
			count+=1
		elif test $((16#$(cat "${d}/intel-iommu/ecap") & $2)) -eq 0; then
			if test "${count}" -gt 0; then
				echo "${DMA_TESTNAME} Intel IOMMU ${1} feature inconsistent in ecap registers"
				return 1
			fi
		fi
	done

	if test "${count}" -eq 0; then
		echo "${DMA_TESTNAME} Intel IOMMU does not support the ${1} feature"
		return 1
	fi

	return 0
}

# PRS bit is 1 << 29
is_intel_prs_supported ()
{
	is_intel_feature_supported "prs" $((1 < 29))
	return $?
}

# PASID bit is 1 << 40
is_intel_pasid_supported ()
{
	is_intel_feature_supported "pasid" $((1 << 40))
	return $?
}

# SM bit is 1 << 43
is_intel_sm_supported ()
{
	is_intel_feature_supported "smts" $((1 << 43))
	return $?
}

is_intel_sm_enabled ()
{
	if is_intel_sm_supported; then
		if journalctl -k | grep -q "DMAR: Enable scalable mode if hardware supports"; then
			if journalctl -k | grep -qE "dmar[0-9]+ SVM disabled, "; then
				test_complete "${DMA_TESTNAME}-intel-sm-enabled-check" "SKIP" "SVM disabled, due to platform incompatibility"
			fi
			return 0
		else
			return 1
		fi
	else
		if journalctl -k | grep -qE "dmar[0-9]+ SVM disabled, "; then
			test_complete "${DMA_TESTNAME}-intel-sm-enabled-check" "SKIP" "SVM disabled, due to platform incompatibility"
		fi
	fi

	return 1
}

grubby_update_arg ()
{
	grubby --args="${1}" --update-kernel=DEFAULT
	echo "${DMA_TESTNAME} grubby setting ${1}"
}

grubby_remove_arg ()
{
	grubby --remove-args="${1}" --update-kernel=DEFAULT
	echo "${DMA_TESTNAME} grubby removing ${1}"
}

intel_iommu_grub_setup ()
{
	case "${1}" in
		"lazy" | "strict" | "pt" | "forcedac")
			grubby_update_arg "intel_iommu=on"
			;;
		"sm-on-lazy" | "sm-on-strict" | "sm-on-pt")
			grubby_update_arg "intel_iommu=on,sm_on"
			;;
		"sm-off-lazy" | "sm-off-strict" | "sm-off-pt")
			grubby_update_arg "intel_iommu=on,sm_off"
			;;
		"sp_off")
			grubby_update_arg "intel_iommu=on,sp_off"
			;;
		"igfx_off")
			grubby_update_arg "intel_iommu=on,igfx_off"
			;;
		*)
			test_complete "${DMA_TESTNAME}-intel-iommu-grub-setup" "FAIL" "intel_iommu_grub_setup called with ${1}"
			;;
	esac
}

intel_iommu_enable ()
{
	if is_vendor "intel"; then
		grubby_update_arg "intel_iommu=on"
	fi
}

amd_iommu_grub_setup ()
{
	case "${1}" in
		"off")
			grubby_update_arg "amd_iommu=off"
			;;
		"pgtbl_v1")
			grubby_update_arg "amd_iommu=pgtbl_v1"
			;;
		"pgtbl_v2-lazy" | "pgtbl_v2-strict" | "pgtbl_v2-pt")
			grubby_update_arg "amd_iommu=pgtbl_v2"
			;;
		"force_enable")
			grubby_update_arg "amd_iommu=force_enable"
			;;
		"lazy" | "strict" | "pt" | "forcedac")
			;;
		*)
			test_complete "${DMA_TESTNAME}-amd-iommu-grub-setup" "FAIL" "amd_iommu_grub_setup called with ${1}"
			;;
	esac
}

arm_smmu_grub_setup ()
{
	#check is disable_bypass=n is being used
	repat="arm-smmu.*disable_bypass=n"

	if ! test -f "${DMA_STATEDIR}/pre_arch_iommu)"; then
		return
	fi

	if [[ "$(cat ${DMA_STATEDIR}/pre_arch_iommu)" =~ ${repat} ]]; then
		grubby_update_arg "$(cat ${DMA_STATEDIR}/pre_arch_iommu)"
	fi
}

# $1 - iommu config to setup
grub_setup ()
{
	# configure arch/vendor specific bits
	case "$(uname -m)" in
		"x86_64")
			if is_vendor "intel"; then
				intel_iommu_grub_setup "${1}"
			else
				amd_iommu_grub_setup "${1}"
			fi
			;;
		"aarch64")
			arm_smmu_grub_setup "${1}"
			;;
	esac

	# configure iotlb invalidation
	case "${1}" in
		"strict" | "sm-on-strict" | "sm-off-strict" | "pgtbl_v2-strict")
			grubby_update_arg "iommu.strict=1"
			;;
		*)
			grubby_update_arg "iommu.strict=0"
			;;
	esac

	# configure default dma domain type
	case "${1}" in
		"pt" | "sm-on-pt" | "sm-off-pt" | "pgtbl_v2-pt")
			grubby_update_arg "iommu.passthrough=1"
			;;
		*)
			grubby_update_arg "iommu.passthrough=0"
			;;
	esac

	# configure forcedac
	case "${1}" in
		"forcedac")
			grubby_update_arg "iommu.forcedac=1"
			;;
		*)
			;;
	esac

	set_phase "reboot"
	sleep 1
	rstrnt-reboot
}

grub_cleanup ()
{
	case "$(uname -m)" in
		"x86_64")
			if is_vendor "intel"; then
				grubby_remove_arg "intel_iommu"
			else
				grubby_remove_arg "amd_iommu"
			fi
			;;
		"aarch64")
			if is_arm_smmu_v3; then
				grubby_remove_arg "arm-smmu-v3"
			else
				grubby_remove_arg "arm-smmu"
			fi
			;;
	esac

	grubby_remove_arg "iommu.passthrough"
	grubby_remove_arg "iommu.strict"
	grubby_remove_arg "iommu.forcedac"
}

grub_pre_save ()
{
	local pre_iommu=()
	local pre_arch_iommu=""
	local iommu_re="^iommu"
	local arch_iommu_re=""

	case "$(uname -m)" in
		"x86_64")
			if is_vendor "intel"; then
				arch_iommu_re="^intel_iommu"
			else
				arch_iommu_re="^amd_iommu"
			fi
			;;
		"aarch64")
			arch_iommu_re="^arm-smmu"
			;;
	esac

	mapfile -d ' ' KPARAMS < <(grubby --info=DEFAULT | grep 'args=' | sed -e 's/args="//' -e 's/"$//')
	for p in "${KPARAMS[@]}"; do
		if [[ ${p} =~ ${iommu_re} ]]; then
			arg=$(sed -e 's/\n//g' -e 's/\s+//g' <<< "${p}")
			pre_iommu+=("${arg}")
		fi
		if ! test -z "${arch_iommu_re}"; then
			if [[ ${p} =~ ${arch_iommu_re} ]]; then
				arg=$(sed -e 's/\n//g' -e 's/\s+//g' <<< "${p}")
				pre_arch_iommu="${arg}"
			fi
		fi
	done

	if ! test -z "${IOMMU_DEBUG}"; then
		if test ${#pre_iommu[@]} -gt 0; then
			echo "${DMA_TESTNAME}: pre_iommu array contents: ${pre_iommu[*]}"
		fi
	fi

	if ! test -z "${pre_arch_iommu}"; then
		echo "${DMA_TESTNAME} storing arch/vendor specific parameters: ${pre_arch_iommu}"
		echo "${pre_arch_iommu}" > "${DMA_STATEDIR}/pre_arch_iommu"
	fi

	if test ${#pre_iommu[@]} -gt 0; then
		echo "${DMA_TESTNAME} Storing iommu parameters: ${pre_iommu[*]}"
		echo "${pre_iommu[@]}" > "${DMA_STATEDIR}/pre_iommu"
	fi

	if ! test -z "${IOMMU_DEBUG}"; then
		if test -f "${DMA_STATEDIR}/pre_arch_iommu"; then
			echo "${DMA_TESTNAME} pre_arch_iommu after storing: $(cat ${DMA_STATEDIR}/pre_arch_iommu)"
		fi

		if test -f "${DMA_STATEDIR}/pre_iommu"; then
			echo "${DMA_TESTNAME} pre_iommu after storing: $(cat ${DMA_STATEDIR}/pre_iommu)"
		fi
	fi
}

grub_exit ()
{
	grub_cleanup

	if test -f "${DMA_STATEDIR}/pre_arch_iommu"; then
		echo "${DMA_TESTNAME} restoring original arch/vendor specific parameters: $(cat ${DMA_STATEDIR}/pre_arch_iommu)"
		param="$(cat ${DMA_STATEDIR}/pre_arch_iommu)"
		grubby_update_arg "${param}"
	fi

	if test -f "${DMA_STATEDIR}/pre_iommu"; then
		echo "${DMA_TESTNAME} restoring original iommu parameters: $(cat ${DMA_STATEDIR}/pre_iommu)"
		param="$(cat ${DMA_STATEDIR}/pre_iommu)"
		grubby_update_arg "${param}"
	fi
}

init_state ()
{
	if ! test -d "${DMA_STATEDIR}"; then
		mkdir -p "${DMA_STATEDIR}"
	fi

	grub_pre_save
}

cleanup_state ()
{
	if test -d "${DMA_STATEDIR}"; then
		rm -rf "${DMA_STATEDIR}"
	fi
	rm -f /mnt/scratchspace/*
}

# $1 - path to check
exists()
{
	[[ -d ${1} ]];
}

# $1 - cpu vendor string to match
is_vendor ()
{
	if lscpu | grep "^Vendor ID" | grep -qi "${1}"; then
		return 0
	else
		return 1
	fi
}

get_vendor ()
{
	local vendor=""

	vendor="$(lscpu | grep -E '^Vendor ID:' | awk -F':' '{print $2;}' | sed -e 's/^[ \t]*//g' -e 's/[ \t]*$//g')"
	echo "${vendor}"
}

# $1 - expected reboot count
check_rebootcount ()
{
	[[ "${RSTRNT_REBOOTCOUNT}" = "${1}" ]]
}

check_reboot ()
{
	if ! check_rebootcount "${config_reboots[$(get_config)]}"; then
		fail_abort "${DMA_TESTNAME}-check-reboot" "Unexpected reboot"
	fi
}

# $1 - phase name to compare against
check_phase ()
{
	[[	"$(get_phase ${1})" == "${1}" ]];
}

check_config ()
{
	[[	"$(get_config ${1})" == "${1}" ]];
}

# $1 - phase name to set state to
set_phase ()
{
	echo "${1}" > "${DMA_STATEDIR}/phase"
}

get_phase ()
{
	echo "$(cat ${DMA_STATEDIR}/phase)"
}

# $1 - config state to compare to
set_config ()
{
	echo "${1}" > "${DMA_STATEDIR}/config"
}

get_config ()
{
	echo "$(cat ${DMA_STATEDIR}/config)"
}

next_phase ()
{
	set_phase "${next_config_phases[$(get_config)]}"
	set_config "${next_configs[$(get_config)]}"
}

fail_abort ()
{
	grub_exit
	cleanup_state
	echo "${1} FAIL/ABORT reason: ${2}"
	rstrnt-report-result "${1}" FAIL
	exit 0
}

warn_abort_recipe ()
{
	grub_exit
	cleanup_state
	echo "${1} WARN/ABORT reason: ${2}"
	rstrnt-report-result "${1}" WARN
	rstrnt-abort recipe
}

test_complete ()
{
	echo "${1} ${2} reason: ${3}"
	grub_exit
	cleanup_state
	if ! test -z $4; then
		rstrnt-report-result --outputfile="${4}" "${1}" "${2}"
	else
		rstrnt-report-result "${1}" "${2}"
	fi

	exit 0
}

test_continue ()
{
	echo "${1} ${2} reason: ${3}"
	if ! test -z $4; then
		rstrnt-report-result --outputfile="${4}" "${1}" "${2}"
	else
		rstrnt-report-result "${1}" "${2}"
	fi
}
