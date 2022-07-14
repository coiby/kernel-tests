#!/bin/bash
###                                                           ###
# This script contains many of the common functions, variables, #
# and constants that RDMA QE uses for test cases.               #
###                                                           ###

##
# Prepend time-stamp to execution log
##
PS4='$(date +"+ [%y-%m-%d %H:%M:%S]") '

## functions #################################################################

##
# This function is to check if there exists RDMA HCA on the test machine
##
function RQA_exist_RDMA_HCA {
    lspci | grep -i -e ConnectX -e omni -e FastLinQ -e NetXtreme-E -e e810
    return $?
}

##
# This function is to get the hca_id list
##
function RQA_get_hca_id {
    which ibv_devinfo >/dev/null 2>&1 || $PKGINSTALL libibverbs-utils
    ibv_devinfo >/dev/null 2>&1 && echo $(ibv_devinfo -l | sed '1d' | tr -s '\n')
}

##
# This function is to install a package(s) if it isn't already installed
# Arguments: package name or a list of package names
# Example: RQA_pkg_install nfs-utils
#          RQA_pkg_install nfs-utils nfsometer
##
function RQA_pkg_install {
    PKG_LIST=""
    for p in "$@";
    do
        rpm -q "$p" || PKG_LIST="${PKG_LIST} ${p}"
    done

    if [ ! -z "$PKG_LIST" ]; then
        $PKGINSTALL $PKG_LIST
    fi
}

##
# Returns the RHEL or Fedora release the host is provisioned to
# Arguments: none
##
function RQA_get_rhel_release {
    grep -o '[0-9]*\.*[0-9]*' /etc/redhat-release
}

##
# Returns the RHEL major release the host is provisioned to.  For Fedora,
# the return value will be equivalent to RQA_get_rhel_release's.
# Arguments: none
##
function RQA_get_rhel_major {
    echo $(RQA_get_rhel_release) | awk -F "." '{print $1}'
}

##
# Returns the RHEL minor release the host is provisioned to.  For Fedora,
# the return value will be empty.
# Arguments: none
##
function RQA_get_rhel_minor {
    echo $(RQA_get_rhel_release) | awk -F "." '{print $2}'
}

# determine whether to use yum or dnf
if [[ $(grep -i fedora /etc/redhat-release >/dev/null) || $(RQA_get_rhel_major) -ge 8 ]]; then
    export PKGINSTALL="dnf install -y --setopt=strict=0 --nogpgcheck"
    export PKGREMOVE="dnf remove --noautoremove -y"
else
    export PKGINSTALL="yum install -y --skip-broken --nogpgcheck"
    export PKGREMOVE="yum remove -y"
fi
