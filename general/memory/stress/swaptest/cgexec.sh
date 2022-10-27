#!/bin/bash

cgroup_version=$1
cgroup_dir=$2

usage()
{
	echo -e "Usage:\n  $0 <cgruop_versionsion_num> <cgroup_dir> <command to run>"
}

if [ $# -lt 3 ]; then
	usage
	exit 1
fi

if ! [ "$cgroup_version" -eq 1 -o "$cgroup_version" -eq 2 ]; then
	echo -e "$0: cgroup_version is not correct: please provide it with one of the version nums in '1' and '2'\n"
	usage
	exit 1
fi

shift 2

if [ "$cgroup_version" = 1 ]; then
	if ! test -f $cgroup_dir/tasks; then
		echo -e "$0: cgroup_dir is not correct: no $cgroup_dir/tasks\n"
		usage
		exit 1
	fi
	echo $$ > $cgroup_dir/tasks
elif [ "$cgroup_version" = 2 ]; then
	if ! test -f $cgroup_dir/cgroup.procs; then
		echo -e "$0: cgroup_dir is not correct: no $cgroup_dir/cgroup.procs\n"
		usage
		exit 1
	fi
	echo $$ > $cgroup_dir/cgroup.procs
fi

echo -e "$0: Executing \"$*\" under cgroup $(cat /proc/$$/cgroup)"
exec $*

