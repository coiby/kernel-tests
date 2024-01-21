#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: memory test helper functions
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc. All rights reserved.
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

function check_cgroup_version()
{
	[ -n "$CGROUP_VERSION" ] && return

	if mount | grep -qE "^cgroup2"; then
		CGROUP_ROOT=$(mount | awk '/cgroup2/ {print $3; exit}')
		cat $CGROUP_ROOT/cgroup.controllers
		nr_v2_controllers=$(awk '{print NF}' $CGROUP_ROOT/cgroup.controllers)
		if ((nr_v2_controllers > 0)); then
			echo "Using cgroup V2" && CGROUP_VERSION=2
			CGROUP_TASK_FILE=cgroup.procs
		else
			echo "Using cgroup v1"
			CGROUP_VERSION=1
			CGROUP_ROOT=$(mount | grep cgroup | awk '/cgroup /{split($3, a, "cgroup"); print a[1]"cgroup"; exit}')
			CGROUP_TASK_FILE=tasks
		fi
	else
		echo "Using cgroup v1"
		CGROUP_VERSION=1
		CGROUP_ROOT=$(mount | grep cgroup | awk '/cgroup /{split($3, a, "cgroup"); print a[1]"cgroup"; exit}')
		CGROUP_TASK_FILE=tasks
	fi

	gen_cgexec

	CGROUP_EXEC=/usr/bin/cgexec.sh
	export CGROUP_VERSION
	export CGROUP_TASK_FILE
	export CGROUP_ROOT
	export CGROUP_EXEC
}

function __fix_cgroup_dir()
{
	local dir=$1
	local controller=$2

	if [ "$CGROUP_VERSION" = 1 ]; then
		local fixed_controller_dir=$(mount -t cgroup | awk '/'$controller',|'$controller' / {print $3; exit}')
		local tgt_dir=$fixed_controller_dir/$dir/
	elif [ "$CGROUP_VERSION" = 2 ]; then
		local tgt_dir=$CGROUP_ROOT/$dir/
	fi

	shopt -s extglob
	tgt_dir=${tgt_dir%%+(/)}
	shopt -u extglob

	echo $tgt_dir
}

function cgroup_get_path()
{
	local dir=$1
	local controller=$2
	__fix_cgroup_dir $dir "$controller"
}

function cgroup_create()
{
	local cgroup_dir=$1
	local controllers="${2//,/ }"

	local controller_mount
	local ret=0
	local controller
	local cgroup
	local force=0
	local level=0

	if [ "$CGROUP_VERSION" = 1 ]; then
		for controller in $controllers; do
			controller_mount=$(cgroup_get_path / $controller)
			cgroup=$controller_mount/$cgroup_dir
			mkdir -p $cgroup
			[ $? -ne 0 ] && ((ret++))
		done
	elif [ "$CGROUP_VERSION" = 2 ]; then
		# rt cpu group is not working in cgroup v2 in rhel9-Beta, and rt cpu group
		# would be disabled soon in rhel-9 Beta
		if [ "$force" = 1 ] && echo $controllers | grep -q cpu; then
			echo "rt tasks running:"
			ps -AL -o pid,policy,args | grep -E "DL|FIFO|RR"
			local rt_pids=$(ps -AL -o pid,policy,args | grep -E "RR|FF|DL" | grep -Ev "grep|\[" | awk '{print $1}')
			echo "Killing rt tasks" && kill $rt_pids
		fi

		for controller in $controllers; do
			echo "+$controller" >> $CGROUP_ROOT/cgroup.subtree_control
			[ $? -ne 0 ] && ((ret++))
		done
		cgroup=$CGROUP_ROOT/$cgroup_dir

		# if cgroup folder like: $CGROUP_ROOT/A/B/C
		# don't setup cgroup.sub_tree_control for the leaf cgroup(C), only leaf cgroup
		# can be used for running processes, while a leaf cgroup shouldn't provide
		# cgroup.subtree_control
		local sub_path=$CGROUP_ROOT
		local sub_dir_name
		local nr_sub_dirs=$(echo ${cgroup_dir//\// } | awk '{print NF}')
		for sub_dir_name in ${cgroup_dir//\// }; do
			[ "$sub_dir_name" = "${cgroup_dir//\/ }" ] && break
			sub_path+="/$sub_dir_name"
			((++level))
			test -d $sub_path || mkdir $sub_path
			((level >= nr_sub_dirs)) && break
			for controller in $controllers; do
				echo "+$controller" >> $sub_path/cgroup.subtree_control || ((ret++))
				[ $? -ne 0 ] && ((ret++))
			done
		done

		mkdir -p $cgroup
		grep -qw $controller $cgroup/cgroup.controllers
		if [ $? -ne 0 ]; then
			echo "$cgroup/cgroup.controllers: $controller is not enabled"
			grep -qw $controller $cgroup/cgroup.controllers || { return 1; }
		fi
	fi

	echo $FUNCNAME: succeed to create cgroup $cgroup

	return $ret
}

function cgroup_set_memory()
{
	set -x
	local cgroup_dir=$1
	local mem_size_max=$2 # can be format like 1g,2m,3t
	local swap_size_max=$3 # can be format like 1g,2m,3t, the unit *must* be same with mem_size_max

	function to_bytes()
	{
		local unit=$(echo ${1,,} | grep -Eo "k|m|g|t|p")
		local value=$(echo ${1,,} | grep -Eo "[0-9]+")
		local rval
		case $unit in
			"k")
				rval=$(echo $value \* 1024 | bc)
				shift
				;;
			"m")
				rval=$(echo $value \* 1024 \* 1024 | bc)
				shift
				;;
			"g")
				rval=$(echo $value \* 1024 \* 1024 \* 1024 | bc)
				shift
				;;
			"t")
				rval=$(echo $value \* 1024 \* 1024 \* 1024 \* 1024 | bc)
				shift
				;;
			"p")
				rval=$(echo $value \* 1024 \* 1024 \* 1024 \* 1024 \* 1024 | bc)
				shift
				;;
			*)
				rval=$1
				shift
				;;
		esac
		echo $rval
	}

	if [ "$CGROUP_VERSION" = 1 ]; then
		set -x
		if grep -q [56].[0-9] /etc/redhat-release; then
			local mem_size_max=$(echo $(to_bytes $mem_size_max) $(to_bytes $swap_size_max) | awk  '{print $1+$2}')
		else
			local mem_swap_max=$(echo | awk -v IGNORECASE=1 -v a=$mem_size_max -v b=$swap_size_max \
				'{split(a, val1,"m|g|k|t|p",sep1); split(b,val2,"m|g|k|t|p",sep2); printf("%d%s\n",val1[1]+val2[1],sep1[1])}')
			cgroup=$CGROUP_ROOT/memory/$cgroup_dir
			mkdir -p $cgroup
			echo ${mem_size_max} > $cgroup/memory.limit_in_bytes
			echo ${mem_swap_max} > $cgroup/memory.memsw.limit_in_bytes
		fi
		set +x
	elif [ "$CGROUP_VERSION" = 2 ]; then
		local mem_oom_group=1
		set -x
		cgroup=$CGROUP_ROOT/$cgroup_dir
		mkdir -p $cgroup
		echo ${mem_size_max} > $cgroup/memory.max
		echo ${swap_size_max} > $cgroup/memory.swap.max
		echo ${mem_oom_group} > $cgroup/memory.oom.group
		set +x
	fi
	set +x
}

declare -A CGROUP_FILE_MAP
CGROUP_FILE_MAP["memory.limit_in_bytes"]="memory.max"
CGROUP_FILE_MAP["memory.memsw.limit_in_bytes"]="memory.swap.max"
CGROUP_FILE_MAP["tasks"]="cgroup.procs"
CGROUP_FILE_MAP["cpu.shares"]="cpu.weight"
CGROUP_FILE_MAP["cpu.cfs_quota_us"]="cpu.max"

function v1_v2_file_map()
{
	local file_name=$1
	local file_dir=$2
	local k

	test -f $file_dir/$file_name && echo "$file_name" && return

	if echo "${CGROUP_FILE_MAP[*]}" | grep -qw "$file_name"; then
		for k in ${!CGROUP_FILE_MAP[*]}; do
			if [ ${CGROUP_FILE_MAP[$k]} = "$file_name" ]; then
				echo "$FUNCNAME: convert v2 file $file_name to v1 file $k" 1>&2
				echo $k
				return
			fi
		done
	elif echo "${!CGROUP_FILE_MAP[*]}" | grep -qw "$file_name"; then
		echo "$FUNCNAME: convert v1 file $file_name to v2 file ${CGROUP_FILE_MAP["$file_name"]}" 1>&2
		echo "${CGROUP_FILE_MAP["$file_name"]}" && return
	fi

	echo $1
}

function cgroup_get_file()
{
	local dir=$1
	local controllers="${2//,/ }"
	local other_files="${3//,/ }"
	local has_header=${4:-0}
	local extra
	local extra_0
	local cggf

	# if it's a cgroup print, show the headers
	[ $# -eq 2 ] && has_header=1

	local fixed_filenames
	local controller
	local path
	for cggf in $other_files; do
		controller=${cggf%%.*}
		path=$(cgroup_get_path $dir $controller)
		[ -n "$fixed_filenames" ] && fixed_filenames+=" "
		fixed_filenames+=$(v1_v2_file_map $cggf $path)
	done

	other_files=$fixed_filenames
	extra_0=" -maxdepth 1"
	if [ "$other_files" != "" ]; then
		extra=" -name ${other_files// / -o -name }"
	fi
	if [ "$CGROUP_VERSION" = 1 ]; then
		for controller in $controllers; do
			local tgt_dir=$(__fix_cgroup_dir $dir "$controllers")
			for cggf in $(find $tgt_dir $extra_0 -type f $extra); do
				nl=$(wc -l $cggf | awk '{print $1}')
				if ((nl == 1)); then
					file_value=$(cat $cggf)
					if ((has_header)); then
						echo -n "$(basename $cggf)="
					fi
					echo "$file_value"
				elif ((nl == 0)); then
					file_value=$(cat $cggf)
					if ((has_header)); then
						echo -n "$(basename $cggf)"
					fi
					echo "$file_value"
				else
					echo "$(basename $cggf):"
					cat $cggf | awk '{printf("\t%s\n", $0)}'
				fi
			done
		done
	elif [ "$CGROUP_VERSION" = 2 ]; then
		local tgt_dir=$(__fix_cgroup_dir $dir "$controllers")
		for cggf in $(find $tgt_dir $extra_0 -type f $extra); do
			nl=$(wc -l $cggf | awk '{print $1}')
			if ((nl == 1)); then
				file_value=$(cat $cggf)
				if ((has_header)); then
					echo -n "$(basename $cggf)="
				fi
				echo "$file_value"
			elif ((nl == 0)); then
				file_value=$(cat $cggf)
				if ((has_header)); then
					echo -n "$(basename $cggf)="
				fi
				echo "$file_value"
			else
				echo "$(basename $cggf):"
				cat $cggf | awk '{printf("\t%s\n", $0)}'
			fi
		done
	fi

	return 0
}

function cgroup_set_file()
{
	local dir=$1
	local controller=$2

	local ret=0
	local tgt_dir

	shift 2

	tgt_dir=$(__fix_cgroup_dir $dir $controller)
	test -d $tgt_dir

	[ $? -ne 0 ] && echo "No cgroup exist: $tgt_dir !" && return 1

	local file_name
	local file_path
	local file_value
	while [ $# -gt 0 ]; do
		file_name=$(echo $1 | awk -F= '{print $1}')
		file_path=$tgt_dir/$file_name
		file_value=$(echo $1 | awk -F= '{print $2}')
		if ! test -f $file_path; then
			file_name=$(v1_v2_file_map $file_name $tgt_dir)
			file_path=$tgt_dir/$file_name
			test -f $file_path && ret=0 || echo "$FUNCNAME: No $file_name in $tgt_dir"
		fi
		echo $dir: file_name=$file_name, file_value=$file_value
		echo "$file_value" > $file_path || ((ret++))
		shift 1
	done

	return $ret
}

function cgroup_display()
{
	local dir=$1
	local controllers=${2//,/ }
	local controller

	[ -z "$controllers" ] && [ "$CGROUP_VERSION" = 1 ] && echo "controller is not provided" && return 1
	if [ "$CGROUP_VERSION" = 1 ]; then
		for controller in $controllers; do
			local tgt_dir=$(__fix_cgroup_dir "$dir" "$controller")
			test -d $tgt_dir || { echo "$FUNCNAME: $tgt_dir doesnt exist" && return 1; }
			cgroup_get_file $dir $controller "$3"
		done
	else
		cgroup_get_file $dir "$controllers" "$3"
	fi
}

function cgroup_destroy()
{
	local dir=$1
	local controllers="${2//,/ }"

	local path
	local tgt_dir
	local ret=0

	if [ "$CGROUP_VERSION" = 1 ]; then
		local fail_controllers=""
		local success_controllers=""
		for controller in $controllers; do
			tgt_dir=$(__fix_cgroup_dir $dir "$controller")
			test -d $tgt_dir || { echo "$tgt_dir doesn't exist!" && return; }
			# kill the tasks in the cgroup
			local nr_tasks=$(wc -l $tgt_dir/$CGROUP_TASK_FILE | awk '{print $1}')
			((nr_tasks > 0)) && kill $(cat $tgt_dir/$CGROUP_TASK_FILE)
			rmdir $tgt_dir
			if [ $? -ne 0 ]; then
				echo "$controller:$tgt_dir failed to remove!"
				fail_controllers+="$controller,"
				((ret++))
			else
				success_controllers+="$controller,"
			fi
		done
		if ((ret==0)); then
			echo "$FUNCNAME: $success_controllers:$tgt_dir succeed to be removed"
		else
			echo "$FUNCNAME: $success_controllers:$tgt_dir fail to be removed"
		fi
	else
		# cgroup v2
		tgt_dir=$(__fix_cgroup_dir $dir "$controller")
		local nr_tasks=$(wc -l $tgt_dir/$CGROUP_TASK_FILE | awk '{print $1}')
		#((nr_tasks > 0)) && kill $(cat $tgt_dir/$CGROUP_TASK_FILE)
		((nr_tasks > 0)) && echo 1 > $tgt_dir/cgroup.kill
		rmdir $tgt_dir || ((ret++))
		if ((ret==0)); then
			echo "$FUNCNAME: $tgt_dir succeed to be removed"
		else
			echo "$FUNCNAME: $tgt_dir fail to be removed"
		fi
	fi
}

# generate a cgexec.sh and locate it in /usr/bin
# Usage:
# cgexec.sh <dir_name> <controllers> <cmd>
function gen_cgexec()
{
	local file=cgexec.sh
	local path=$(pwd)
	local res
	local i

	for i in $(seq 1 10); do
		test -f $path/include/$file && res=$path/include/$file && break
		test -f $path/general/include/$file && res=$path/general/include/$file && break
		path=$path/..
	done

	echo "cgexec.sh in $res"

	\cp $res /usr/bin/ -f
	test -f /usr/bin/cgexec.sh
}

check_cgroup_version

# Test case for the cgroup helper functions
if ((0)); then
	check_cgroup_version
	cgroup_get_path / cpu
	cgroup_create A cpu,memory,pids
	cgroup_set_memory A 1g 2g
	cgroup_display A "cpu" "cpu.weight cpu.cfs_period_us cpu.cfs_quota_us"
	cgroup_set_file A cpu cpu.shares="1000"
	cgroup_get_file A cpu cpu.shares
	cgexec.sh "A" "cpu,memory" stress-ng --cpu 1 -t 10 &
	sleep 12
	cgroup_destroy A cpu,memory,pids
	cgroup_create A/B/C cpu,memory,pids
	cgexec.sh A/B/C cpu,memory,pids ls
	cgroup_destroy A/B/C cpu,memory,pids
	cgroup_destroy A/B cpu,memory,pids
	cgroup_destroy A cpu,memory,pids
	unset CGROUP_VERSION
fi
