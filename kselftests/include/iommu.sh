#!/bin/bash
# We have some systems in the cki pool that fail to allocate hugepages
# So skip the test if we land on one of those systems as it is going to
# fail when it gets to the cases which make use of hugepages.

do_iommu_config()
{
    declare -i freehp=0
    freehp_pat='HugePages_Free: *([0-9]+)'

    if [[ $(grep HugePages_Free /proc/meminfo) =~ ${freehp_pat} ]]; then
        freehp="${BASH_REMATCH[1]}"
    fi

    if [[ "${freehp}" -lt "64" ]]; then
        test_skip_exit "Not enough hugepages available (${freehp}). Skipping test."
        return 1
    fi
}
