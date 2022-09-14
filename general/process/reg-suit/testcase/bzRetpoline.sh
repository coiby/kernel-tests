#!/bin/bash
function bzRetpoline()
{
	local keyword="generic"
	lscpu | grep AMD && keyword="AMD"
	uname -m | grep x86 || return
	rlIsRHEL ">=8" || return
	rlLog "https://bugzilla.redhat.com/show_bug.cgi?id=1535661"
	rlRun -l "cat /sys/devices/system/cpu/vulnerabilities/spectre_v2"
	local fam=$(awk -F: '/family/ {gsub(" ","",$2);print $2;exit} ' /proc/cpuinfo)
	local model=$(awk -F: '/model/ {gsub(" ","",$2);print $2;exit} ' /proc/cpuinfo)
	local stepping=$(awk -F: '/stepping/ {gsub(" ","",$2);print $2;exit} ' /proc/cpuinfo)
	local mod_name=$(awk -F: '/model name/ {gsub("^ ","", $2);print $2;exit} ' /proc/cpuinfo)
	# For skylake, IBRS is default.
	rlLog "Running cpu: $mod_name: $fam $model $stepping"
	if lscpu | grep -i KVM; then
		mark_skip "$model kvm"
		return
	fi

	if uanem -r | grep rt; then
		mark_skip "kernel-rt"
		return
	fi
	if ((fam == 6)); then
		if ((model==78)) || ((model==85)) || ((model==95)) || ((model==142)) || ((model==158)); then
			rlLog "Running Skylake cpu: $fam $model $stepping"
			if grep ibrs_enhance /proc/cpuinfo; then
				rlRun -l "grep 'Mitigation: Enhanced IBRS' /sys/devices/system/cpu/vulnerabilities/spectre_v2" 0 "make sure IBRS is enabled for Skylake."
			elif grep ibrs -wo /proc/cpuinfo; then
				rlRun -l "grep -e 'Mitigation:.*IBRS_FW' /sys/devices/system/cpu/vulnerabilities/spectre_v2" 0 "make sure IBRS_FW is enabled for Skylake."
			fi
		elif grep ibrs_enhance /proc/cpuinfo; then
			rlRun -l "grep 'Mitigation: Enhanced IBRS' /sys/devices/system/cpu/vulnerabilities/spectre_v2" 0 "make sure IBRS is enabled for Skylake+ or Atom"
		else
			# commit 2681c0ad1a (x86/speculation: Rename RETPOLINE_AMD to RETPOLINE_LFENCE) 4.18.0-72.5.1.el8
			# format of Retpoline is updated.
			rlRun -l "grep -e 'Mitigation: Full $keyword retpoline' -e 'Mitigation: Retpolines' /sys/devices/system/cpu/vulnerabilities/spectre_v2" 0 "make sure retpoline is enabled."
		fi
	fi
}
