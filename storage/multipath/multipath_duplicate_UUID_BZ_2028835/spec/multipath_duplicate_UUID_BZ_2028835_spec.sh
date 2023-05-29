#!/bin/bash
eval "$(shellspec - -c) exit 1"

create_multipath_output() {
    cat << 'EOF' > multipath_output
mpatha (333333330000007d0) dm-0 Linux,scsi_debug
size=100M features='0' hwhandler='1 alua' wp=rw
|-+- policy='service-time 0' prio=50 status=enabled
| `- 3:0:0:0 sdb 8:16 active ready running
|-+- policy='service-time 0' prio=10 status=enabled
| `- 4:0:0:0 sdc 8:32 active ready running
|-+- policy='service-time 0' prio=1 status=enabled
| `- 2:0:0:0 sda 8:0  active ready running
`-+- policy='service-time 0' prio=1 status=enabled
  `- 5:0:0:0 sdd 8:48 active ready running
EOF
}

Mock service
    echo "service $*"
    exit 0
End

Mock mpathconf
    echo "mpathconf $*"
    exit 0
End

Mock multipath
    echo "multipath $*"
    if [ "$1" == "-ll" ]; then
        cat "multipath_output"
    fi
    exit 0
End

Mock udevadm
    echo "udevadm $*"
    echo "${UDEVADM_OUTPUT:-}"
End

Mock rlRun
    echo "rlRun $*"
    # in case of multipath -ll command we want it to try
    # to execute the mocked multipath command
    if [[ "$1" =~ "multipath -ll" ]]; then
        eval "$*"
    fi
End

Mock rm
    echo "rm $*"
    exit 0
End

Describe 'multipath_duplicate_UUID_BZ_2028835'
    create_multipath_output

    It "can pass run_test"
        # make sure it contains the expected value the test uses
        export UDEVADM_OUTPUT="DM_MULTIPATH_DEVICE_PATH=1"

        When run script storage/multipath/multipath_duplicate_UUID_BZ_2028835/runtest.sh

        The first line should include "rlJournalStart"
        The second line should include "rlPhaseStartTest"
        The line 3 should equal "yum -y install device-mapper-multipath"
        The line 4 should equal "mpathconf --enable"
        The line 5 should equal "rm -rf /etc/multipath/wwids"
        The line 6 should equal "service multipathd restart"
        # multipath output for first device in the multipath
        The line 20 should include 'rlRun multipath -ll | grep -A 10 scsi_debug | grep -oE "sd." | awk "NR==1"'
        The line 21 should include 'sdb'
        # multipath output for second device in the multipath
        The line 22 should include 'rlRun multipath -ll | grep -A 10 scsi_debug | grep -oE "sd." | awk "NR==2"'
        The line 23 should include 'sdc'
        # multipath output for third device in the multipath
        The line 24 should include 'rlRun multipath -ll | grep -A 10 scsi_debug | grep -oE "sd." | awk "NR==3"'
        The line 25 should include 'sda'
        # multipath output for forth device in the multipath
        The line 26 should include 'rlRun multipath -ll | grep -A 10 scsi_debug | grep -oE "sd." | awk "NR==4"'
        The line 27 should include 'sdd'
        # udevadm part
        The line 28 should include 'DM_MULTIPATH_DEVICE_PATH=1'
        The line 29 should include 'DM_MULTIPATH_DEVICE_PATH=1'
        The line 30 should include 'DM_MULTIPATH_DEVICE_PATH=1'
        The line 31 should include 'DM_MULTIPATH_DEVICE_PATH=1'
        # make sure pass message is in the log
        The stdout should include "rlPass ------- PASS,all paths always return: DM_MULTIPATH_DEVICE_PATH=1 ------"
        # make sure beakerlib end steps are executed
        The stdout should include "rlPhaseEnd"
        The stdout should include "rlJournalPrintText"
        The stdout should include "rlJournalEnd"
        The status should be success
    End

    It "can detect failure run_test"
        When run script storage/multipath/multipath_duplicate_UUID_BZ_2028835/runtest.sh
        # make sure fail message is in the log
        The stdout should include "rlFail ------- FAIL, not all paths always return: DM_MULTIPATH_DEVICE_PATH=1 -------"
        # make sure beakerlib end steps are executed
        The stdout should include "rlPhaseEnd"
        The stdout should include "rlJournalPrintText"
        The stdout should include "rlJournalEnd"
        The status should be success
    End
End

