#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include cki_lib/libcki.sh

Describe 'cki_run'
    It 'runs simple commands'
        export command="ls -allh *"
        When call cki_run "$command"
        The stdout should be present
        The first line should start with "[ "
        The first line should include "] Running: 'ls -allh *'"
        The status should be success
    End

    It 'runs commands with globing expansion'
        export command="ls -allh *"
        # shellcheck disable=SC2086
        # The globing is intentional
        When call cki_run $command
        The stdout should be present
        The first line should start with "[ "
        The first line should include "] Running: 'ls -allh "
        The status should be success
    End

    It 'runs commands with pipe'
        # shellcheck disable=SC2089
        export command="date -d @1670405721 | cut -d ' ' -f 1"
        When call cki_run "$command"
        The stdout should be present
        The first line should start with "[ "
        The first line should include "] Running: 'date -d @1670405721 | cut -d ' ' -f 1'"
        The second line should equal "Wed"
        The lines of stdout should equal 2
        The status should be success
    End

    It 'reports failure if command exits with failure'
        export command="touch invalid/path/new_file"
        When call cki_run "$command"
        The stdout should be present
        # on rhel6 it outputs: `invalid/path/new_file'
        # on rhel7 it outputs: ‘invalid/path/new_file’
        # on newer bash it outputs: 'invalid/path/new_file'
        The first line of stderr should include "touch: cannot touch"
        The first line of stderr should include "invalid/path/new_file"
        The first line of stderr should include "No such file or directory"
        The status should be failure
    End
End

Describe 'cki_download_kernel_src_rpm'
    dnf(){
        if [[ "${1}" == "repoquery" ]]; then
            echo "${MOCK_PACKAGE_NAME}"
        else
            echo "dnf $*"
        fi
    }
    uname(){
        echo "${MOCK_UNAME}"
    }
    cki_get_yum_tool(){
        echo "/usr/bin/dnf"
    }
    Parameters
        "kernel" "4.18.0-372.41.1.el8_6.x86_64" "4.18.0-372.41.1.el8_6"
        "kernel-rt" "4.18.0-372.45.1.rt7.202.el8_6.4270_779243631.x86_64+debug" "4.18.0-372.45.1.rt7.202.el8_6.4270_779243631"
        "kernel" "6.0.7-200.fc36" "6.0.7-200.fc36"
    End
    It "Can download srpm from ${2}"
        export MOCK_UNAME="${2}"
        export MOCK_PACKAGE_NAME="${1}-${3}"
        When call cki_download_kernel_src_rpm
        The first line should include "Running: 'dnf download --source ${MOCK_PACKAGE_NAME}'"
    End
End

Describe 'cki_kernel_version'
    Mock uname
        echo "$VERSION"
    End

    It 'supports rhel kernel like 4.18.0-440.el8.x86_64'
        export VERSION="4.18.0-440.el8.x86_64"
        When call cki_kernel_version
        The stdout should equal "4.18.0-440"
    End

    It 'supports rhel debug kernel like 5.14.0-207.el9.x86_64+debug'
        export VERSION="5.14.0-207.el9.x86_64+debug"
        When call cki_kernel_version
        The stdout should equal "5.14.0-207"
    End

    It 'supports rhel cki gcov kernel like 4.18.0-372.37.1.el8_6.test.gcov'
        export VERSION="4.18.0-372.37.1.el8_6.test.gcov"
        When call cki_kernel_version
        The stdout should equal "4.18.0-372.37.1"
    End

    It 'supports fedora kernel like 6.0.7-200.fc36.x86_64'
        export VERSION="6.0.7-200.fc36.x86_64"
        When call cki_kernel_version
        The stdout should equal "6.0.7-200"
    End

    It 'supports cki eln kernel like 6.1.0-0.rc8.bce9332220bd.59.test.eln.aarch64'
        export VERSION="6.1.0-0.rc8.bce9332220bd.59.test.eln.aarch64"
        When call cki_kernel_version
        The stdout should equal "6.1.0-0.rc8.bce9332220bd.59.test"
    End
End

Describe 'cki_kver_ge'
    cki_kernel_version(){
        echo "5.14.0-170"
    }
    It 'confirms that version 5.14.0-170 is >= 5.14.0-169'
        When call cki_kver_ge "5.14.0-169"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is >= 5.14.0-169.1'
        When call cki_kver_ge "5.14.0-169.1"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is >= 5.14.0-170'
        When call cki_kver_ge "5.14.0-170"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is not >= 5.14.0-171'
        When call cki_kver_ge "5.14.0-171"
        The status should equal 1
    End

    It 'confirms that version 5.14.0-170 is not >= 5.14.0-170.1'
        When call cki_kver_ge "5.14.0-170.1"
        The status should equal 1
    End
End

Describe 'cki_kver_gt'
    cki_kernel_version(){
        echo "5.14.0-170"
    }
    It 'confirms that version 5.14.0-170 is > 5.14.0-169'
        When call cki_kver_gt "5.14.0-169"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is > 5.14.0-169.1'
        When call cki_kver_gt "5.14.0-169.1"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is not > 5.14.0-170'
        When call cki_kver_gt "5.14.0-170"
        The status should equal 1
    End

    It 'confirms that version 5.14.0-170 is not > 5.14.0-171'
        When call cki_kver_ge "5.14.0-171"
        The status should equal 1
    End

    It 'confirms that version 5.14.0-170 is not > 5.14.0-170.1'
        When call cki_kver_gt "5.14.0-170.1"
        The status should equal 1
    End
End

Describe 'cki_kver_le'
    cki_kernel_version(){
        echo "5.14.0-170"
    }
    It 'confirms that version 5.14.0-170 is <= 5.14.0-171'
        When call cki_kver_le "5.14.0-171"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is <= 5.14.0-170.1'
        When call cki_kver_le "5.14.0-170.1"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is <= 5.14.0-170'
        When call cki_kver_le "5.14.0-170"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is not <= 5.14.0-169'
        When call cki_kver_le "5.14.0-169"
        The status should equal 1
    End

    It 'confirms that version 5.14.0-170 is not <= 5.14.0-169.1'
        When call cki_kver_le "5.14.0-169.1"
        The status should equal 1
    End
End

Describe 'cki_kver_lt'
    cki_kernel_version(){
        echo "5.14.0-170"
    }
    It 'confirms that version 5.14.0-170 is < 5.14.0-171'
        When call cki_kver_lt "5.14.0-171"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is < 5.14.0-170.1'
        When call cki_kver_lt "5.14.0-170.1"
        The status should equal 0
    End

    It 'confirms that version 5.14.0-170 is not < 5.14.0-170'
        When call cki_kver_lt "5.14.0-170"
        The status should equal 1
    End

    It 'confirms that version 5.14.0-170 is not < 5.14.0-169'
        When call cki_kver_lt "5.14.0-169"
        The status should equal 1
    End

    It 'confirms that version 5.14.0-170 is not < 5.14.0-169.1'
        When call cki_kver_lt "5.14.0-169.1"
        The status should equal 1
    End
End

Describe 'cki_is_kernel_64k'
    Mock uname
        echo "$VERSION"
    End

    It 'kernel like 5.14.0-243.1820_756592390.el9.aarch64+64k is 64k kernel'
        export VERSION="5.14.0-243.1820_756592390.el9.aarch64+64k"
        When call cki_is_kernel_64k
        The status should equal 0
    End

    It 'kernel like 5.14.0-256.el9.aarch64 is not 64k kernel'
        export VERSION="5.14.0-256.el9.aarch64"
        When call cki_is_kernel_64k
        The status should equal 1
    End
End
