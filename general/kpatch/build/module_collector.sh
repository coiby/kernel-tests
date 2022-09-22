#! /bin/bash
built_kpatch_patch="/home/kpatch-patch-modules"
KPATCH_MNT="/mnt/kpatch"

curr_dir=$(pwd)
collect_dir="${curr_dir}/kpatch/test/integration"
done_list=""

while true; do
    for p in ${collect_dir}/*.ko; do
	    if (echo ${done_list} | grep -wq $p) || ! [ -f "$p" ]; then
            continue
        fi
        echo "Saving $p to $KPATCH_MNT/$(uname -r)"
        \cp $p ${built_kpatch_patch}/
        done_list+="$p          "
    done
    sleep 120
done
