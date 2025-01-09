#!/bin/bash


do_sched_ext_run()
{
    if grep isolcpus /proc/cmdline; then
        # https://lore.kernel.org/all/Zny_5syk1K74HP0D@slm.duckdns.org/
        rlLog "sched_ext not compatible with isolcpus"
        return 0
    fi

    # get the list of available tests from the Makefile
    pushd -- $(find ../SOURCES -type d -path "*selftests/sched_ext")
    sed '/sched_ext:runner/d' -i "$EXEC_DIR"/kselftest-list.txt
    tests=$(make -p | grep auto-test-targets | awk -F ':= ' '{print $NF}')
    for _test in $tests; do
        echo "sched_ext:$_test" >> "$EXEC_DIR"/kselftest-list.txt
    done
    popd

    # run the tests individually to keep the dmesg separate
    pushd ${EXEC_DIR}

    rlPhaseStartTest "sched_ext: enable_seq"
    f_enable_seq=/sys/kernel/sched_ext/enable_seq
    dmesg -C
    enable_seq_0=$(cat $f_enable_seq)
    rlLog "enable_seq_0: ${enable_seq_0}"
    rlLog "Loading a minimal sched, count of enabled_seq should plus 1"
    rlRun "sched_ext/runner -t minimal"
    enable_seq_1=$(cat $f_enable_seq)
    rlLog "enabled_seq_1: ${enable_seq_0}"
    rlAssertEquals "Check the count of enable_seq has been incremented by 1" \
                   "$enable_seq_1" "$((enable_seq_0 + 1))"
    rlRun "dmesg"
    rlPhaseEnd

    for _test in $(grep '^sched_ext' kselftest-list.txt); do
        rlPhaseStartTest "$_test"
        dmesg -C
        rlRun "sched_ext/runner -t ${_test/sched_ext:/}"
        rlRun "dmesg"
        rlPhaseEnd
    done
    popd
}
