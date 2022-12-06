#!/bin/bash
eval "$(shellspec - -c) exit 1"

Describe 'is_kvm'
    Include distribution/ltp/include/knownissue.sh
    # mock the command used by is_kvm
    # to check if virt-what is installed
    # 'command -v virt-what'
    command(){
        # mock to seem virt-what is installed
        return "$COMMAND_RESULT"
    }
    Mock virt-what
        echo "$VIRT_WHAT"
    End
    # not a kvm
    It 'is_kvm for not kvm machine'
        export COMMAND_RESULT=0
        export VIRT_WHAT=""
        When call is_kvm
        The status should be failure
    End
    # is kvm
    It 'is_kvm for a kvm machine'
        export COMMAND_RESULT=0
        export VIRT_WHAT="kvm"
        When call is_kvm
        The status should be success
    End
    It 'is_kvm when virt-what is not installed'
        export COMMAND_RESULT=1
        When call is_kvm
        The status should be failure
    End
End

Describe 'tcase_exclude'
    Include distribution/ltp/include/knownissue.sh
    exclude() {
        echo -e "test1\ntest2\ntest3" | tcase_exclude distribution/ltp/lite/configs/RHELKT1LITE*
    }
    It 'tcase_exclude multiple config files'
        When call exclude
        The first line of output should equal "Excluding test1 form LTP runtest file"
        The second line of output should equal "Excluding test2 form LTP runtest file"
        The third line of output should equal "Excluding test3 form LTP runtest file"
        The status should be success
    End
End

