#!/bin/sh

# process_kpp_nvr var_name1 ... var_nameN.
function process_kpp_nvr()
{
	local kpatch_patch_nvr=$1
	test -z "$kpatch_patch_nvr" && return
	# Return value
	local ret_var_mod=$2
	local ret_var_kpatchurl=$3
	local ret_var_kpatchurl_src=$4
	local ret_var_kpatchurl_released=$5
	local ret_var_kpatch_kernel_vr=$6
	local arch=$(uname -m)
	# NVR related parse.
	local kpatch_patch_name=$(echo $kpatch_patch_nvr | cut -d- -f1,2,3,4)
	local kpatch_patch_version=$(echo $kpatch_patch_nvr | cut -d- -f5)
	local kpatch_patch_release=$(echo $kpatch_patch_nvr | cut -d- -f6)
	local kpatch_kmod_name=$(echo kpatch_${kpatch_patch_name//kpatch-patch-}-${kpatch_patch_version}-${kpatch_patch_release//.el*} | sed 's/\.\|-/_/g')
	# shellcheck disable=SC2154
	local kpatch_patch_srcbase=${kpatch_url_root}/${kpatch_patch_name}/${kpatch_patch_version}/${kpatch_patch_release}/src
	local kpatch_patch_rpmbase=${kpatch_url_root}/${kpatch_patch_name}/${kpatch_patch_version}/${kpatch_patch_release}/$arch
	local kpatch_kernel_vr=$(echo $kpatch_patch_name | cut -d- -f3- | sed 's/_/\./g').${kpatch_patch_release##*.}

	# These can be provided by job submitter, if so, they are useless.
	local mod=${kpatch_kmod_name}
	local patchrpm=${kpatch_patch_nvr}.${arch}.rpm
	local patchsrpm=$kpatch_patch_srcbase/${kpatch_patch_nvr}.src.rpm
	local patchurl=$kpatch_patch_rpmbase/${patchrpm}
	local release_number=$(echo $kpatch_patch_release | cut -d . -f1)
	local release_end_str=$(echo $kpatch_patch_release | cut -d . -f2)

	[ -n "$ret_var_mod" ] && eval ${ret_var_mod}="$mod"
	[ -n "$ret_var_kpatchurl" ] && eval ${ret_var_kpatchurl}="$patchurl"
	[ -n "$ret_var_kpatchurl_src" ] && eval ${ret_var_kpatchurl_src}="$patchsrpm"
	[ -n "$ret_var_kpatch_kernel_vr" ] && eval ${ret_var_kpatch_kernel_vr}="$kpatch_kernel_vr"
	if [ -n "$ret_var_kpatchurl_released" ]; then
		local kpatch_baseline_url
		local kpatch_patch_baselines
		local r
		for ((r=1; r < release_number; r++)); do
			kpatch_baseline_url="${kpatch_url_root}/${kpatch_patch_name}/${kpatch_patch_version}/${r}.${release_end_str}/${arch}"
			kpatch_baseline_url+="/${kpatch_patch_name}-${kpatch_patch_version}-${r}.${release_end_str}"
			kpatch_baseline_url+=".${arch}.rpm"
			kpatch_patch_baselines+="$kpatch_baseline_url "
		done
		eval ${ret_var_kpatchurl_released}=\""$kpatch_patch_baselines"\"
	fi
}

function kpatch_modules_info()
{
	loaded_modules=$(kpatch list  | awk '/Loaded/, /Installed/ {if ($0 ~ /kpatch_/) print}')
	installed_modules=$(kpatch list  | awk '/Installed/, /*/ {if ($0 ~ /kpatch_/) print $1}')
}

function cleanup_kpatch_patch_rpms()
{
	local kpatch_patch
	for kpatch_patch in $(rpm -qa | grep kpatch-patch | grep -v debuginfo); do
		rlRun "rpm -e $kpatch_patch"
	done
}

function cleanup_ftrace_functions()
{
	rlRun "echo nop > /sys/kernel/debug/tracing/current_tracer"
	rlRun "echo > /sys/kernel/debug/tracing/set_ftrace_filter"
	rlRun "echo > /sys/kernel/debug/tracing/set_event"
}

