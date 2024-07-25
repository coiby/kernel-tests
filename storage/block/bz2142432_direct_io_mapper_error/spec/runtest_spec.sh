#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include storage/block/bz2142432_direct_io_mapper_error/runtest.sh

Describe '/block/bz2142432_direct_io_mapper_error - get_disk'
    ls() {
        echo "/dev/sda"
        echo "/dev/sdb"
        echo "/dev/sdc"
    }

    rlRun() {
        echo "rlRun $*"
    }

    check_log() {
        echo "check_log"
    }

    It "can get_disk report pass"
        cat(){
            echo  "8        0  976762584 sda"
            echo  "8        0  976762584 sda1"
            echo  "8        0  976762584 sda2"
            echo  "8        0  976762584 sdb"
            echo  "8        0  976762584 sdc"
        }
        When call get_disk
        The line 1 should equal "will get disk to create raid container and raid "
        The line 2 should equal "sdb have no partition"
        The line 3 should equal "sdc have no partition"
        The stderr should end with ""
        The status should be success
    End

    It "can get_disk report skip"
        cat(){
            echo  "8        0  976762584 sda"
            echo  "8        0  976762584 sda1"
            echo  "8        0  976762584 sda2"
            echo  "8        0  976762584 sdb"
        }
        When call get_disk
        The line 1 should equal "will get disk to create raid container and raid "
        The line 4 should equal "not enough free devices to run the test"
        The stderr should end with ""
        The status should equal 2
    End

    It "can run_test"
        get_disk(){
            return 1
        }

        cat() {
            echo "cat $*"
        }

        echo "#!/bin/bash" > a.out
        chmod +x a.out
        When call run_test
        The line 1 should equal "rlRun parted -s /dev/ mklabel gpt mkpart xfs 1M 50G"
        The status should be success
    End

    It "can run_test report skip"
        get_disk(){
            return 2
        }
        When call run_test
        The line 1 should equal "skip test as there is no free device"
        The status should equal 2
    End
End
