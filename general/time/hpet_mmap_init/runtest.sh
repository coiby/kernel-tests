#!/bin/bash

TEST="general/time/hpet_mmap_init"

function runtest()
{
    # make sure HPET_MMAP config enabled
    grep CONFIG_HPET_MMAP /boot/config-$(uname -r)
    if [ $? -ne 0 ]; then
        echo "Current kernel does not enable CONFIG_HPET_MMAP parameter." | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST "SKIP" "0"
        exit 0
    fi

    if [[ $RSTRNT_REBOOTCOUNT -eq 0 ]]; then
        cat /proc/cmdline | tee -a $OUTPUTFILE
        echo "Add hpet_mmap=1 parameter to bootloader." | tee -a $OUTPUTFILE
        grubby --args="hpet_mmap=1" --update-kernel=/boot/vmlinuz-$(uname -r)
        rstrnt-reboot
    fi

    if [[ $RSTRNT_REBOOTCOUNT -eq 1 ]]; then
        cat /proc/cmdline | tee -a $OUTPUTFILE
        dmesg | grep -i "HPET mmap enabled"
        if [ $? -eq 0 ]; then
            echo "hpet_mmap enabled pass" | tee -a $OUTPUTFILE
            rstrnt-report-result $TEST "PASS" "0"
        else
            dmesg | grep -i "HPET mmap disabled"
            if [ $? -eq 0 ]; then
                echo "hpet_mmap enable failed" | tee -a $OUTPUTFILE
                rstrnt-report-result $TEST "FAIL" "1"
            fi
        fi
        echo "remove hpet_mmap=1" | tee -a $OUTPUTFILE
        grubby --remove-args="hpet_mmap=1" --update-kernel=/boot/vmlinuz-$(uname -r)
        rstrnt-reboot
    fi

    if [[ $RSTRNT_REBOOTCOUNT -eq 2 ]]; then
        echo "Test finished." | tee -a $OUTPUTFILE
    fi
}

# --- Test Start --- #
echo "Based on bz1660796, this case should running on newest kernel-4.18.0-151.el8(RHEL-8.2)." | tee -a $OUTPUTFILE
runtest
exit 0
