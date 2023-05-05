#!/bin/bash
eval "$(shellspec - -c) exit 1"

# Needed to be able to include net.sh
Mock rhel_major
    echo "${MAJOR_RELEASE}"
End
Include kselftests/include/net.sh

Mock which
    echo "which $1"
    exit "$WHICH_EXITCODE"
End

function dnf(){
    bash -x -c 'echo dnf "$@"' -- "$@" 2>&1 >/dev/null | cut -c 8-
    # To inform the package is installed on which command
    WHICH_EXITCODE=0
}

export pkg_mgr="dnf"
export pkg_mgr_inst_string="-y install"

Describe 'kselftests/include/net install_netsniff'
    function rpm(){
        echo "rpm $*"
        return "${RPM_EPEL:-1}"
    }

    It "can install_netsniff krelease 7"
        export WHICH_EXITCODE=1
        export krelease=7
        When call install_netsniff
        The line 1 should equal "which mausezahn"
        The line 2 should equal "dnf -y install jq netsniff-ng"
        The line 3 should equal "which mausezahn"
        The status should be success
    End

    It "can install_netsniff krelease 8 no epel"
        export WHICH_EXITCODE=1
        export krelease=8
        When call install_netsniff
        The line 1 should equal "which mausezahn"
        The line 2 should equal "rpm -q epel-release"
        The line 3 should equal "dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
        The line 4 should equal "dnf -y install jq netsniff-ng"
        The line 5 should equal "dnf -y remove epel-release"
        The line 6 should equal "which mausezahn"
     End

    It "can install_netsniff krelease 9 with epel"
        export WHICH_EXITCODE=1
        export RPM_EPEL=0
        export krelease=9
        When call install_netsniff
        The line 1 should equal "which mausezahn"
        The line 2 should equal "rpm -q epel-release"
        The line 3 should equal "dnf -y install --enablerepo=epel jq netsniff-ng"
        The line 4 should equal "which mausezahn"
     End
End
