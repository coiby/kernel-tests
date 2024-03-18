#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartTest "Check kernel logs for default domain type"
        rlRun "dmesg | grep -q 'iommu: Default domain type: Translated'" 0 "Search dmesg for default domain type" || exit 1
    rlPhaseEnd

    rlPhaseStartTest "Check all configured iommu groups in current hardware"
        # If there is hardware with iommu, directories
        # /sys/kernel/iommu_groups/<n> exist
        if [ -d /sys/kernel/iommu_groups/1 ]; then
            for file in /sys/kernel/iommu_groups/*/type
            do
                # It may be DMA or DMA-FQ
                rlAssertGrep "DMA" "$file"
            done
        fi
    rlPhaseEnd
rlJournalEnd
