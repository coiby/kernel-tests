#!/bin/bash

do_mm_config()
{
	local cfg="/proc/sys/vm/hugetlb_optimize_vmemmap"
	if [ "$VM_SELFTEST_ITEMS" = "hugetlb" ] && test -f $cfg; then
		hugetlb_optimize_vmemmap=$(cat $cfg)
		[ "$hugetlb_optimize_vmemmap" = 1 ] &&
			echo "hugetlb_optimize_vmemmap is enabled by default" &&
				hugetlb_optimize_vmemmap="" && return
		echo "enable vm.hugetlb_optimize_vmemmap"
		echo 1 > $cfg
	fi
}

do_mm_reset()
{
	if [ -n "$hugetlb_optimize_vmemmap" ]; then
		echo "restore vm.hugetlb_optimize_vmemmap"
		echo $hugetlb_optimize_vmemmap > /proc/sys/vm/hugetlb_optimize_vmemmap
	fi
}
