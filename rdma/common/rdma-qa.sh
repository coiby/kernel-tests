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
RDMA_BASE='/sys/class/infiniband'
##
# This function is to check if there exists RDMA HCA on the test machine
##
function RQA_exist_RDMA_HCA {
    if [[ -d ${RDMA_BASE} ]]; then
        return 0
    else
        return 1
    fi
}

##
# This function is to get the hca_id list
##
function RQA_get_hca_id {
    which ibv_devinfo >/dev/null 2>&1 || $PKGINSTALL libibverbs-utils
    ibv_devinfo >/dev/null 2>&1 && ibv_devinfo -l | sed '1d' | tr -s '\n'
}

##
# To get the HCA port physical state
# $1 - device name, e.g. mlx5_0
# $2 - port number, e.g. 1
# return 'LinkUp'
##
function RQA_get_hca_phys_state {
    _devname=$1
    _portnum=$2
    ibstatus ${_devname}:${_portnum} | grep 'phys state' | awk '{print $4}'
}

##
# To get the HCA port logical state, if it's "Active", means the physical connection is up and working,
# and the port has been discovered by the subnet manager.  The port is in a normal operational state.
# $1 - device name, e.g. mlx5_0
# $2 - port number, e.g. 1
# return 'ACTIVE'
##
function RQA_get_hca_logical_state {
    _devname=$1
    _portnum=$2
    ibstatus ${_devname}:${_portnum} | sed 's/^[ \t]*//g' | grep ^state | awk '{print $3}'
}

##
# To check if a HCA port is in a normal operational state
##
function RQA_is_port_normal {
    _devname=$1
    _portnum=$2
    phys_s=$(RQA_get_hca_phys_state ${_devname} ${_portnum})
    logi_s=$(RQA_get_hca_logical_state ${_devname} ${_portnum})
    if [[ ${phys_s} == "LinkUp" ]] && [[ ${logi_s} == "ACTIVE" ]]; then
        return 0
    else
        return 1
    fi
}

##
# To get how many ports of a HCA
# $1 - device name, e.g. mlx5_0
# return the total number of ports of a HCA
##
function RQA_get_ports_number {
    _devname=$1
    port_num=0
    _path="/sys/class/infiniband/${_devname}/ports"
    if [[ ! -d ${_path} ]]; then
        echo 0
        exit
    fi
    for _i in "$_path"/* ; do
        port_num=$((${port_num}+1))
    done
    echo ${port_num}
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

    if [ -n "$PKG_LIST" ]; then
        ${PKGINSTALL} ${PKG_LIST}
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
    RQA_get_rhel_release | awk -F "." '{print $1}'
}

##
# Returns the RHEL minor release the host is provisioned to.  For Fedora,
# the return value will be empty.
# Arguments: none
##
function RQA_get_rhel_minor {
    RQA_get_rhel_release | awk -F "." '{print $2}'
}

##
# Find the appropriate Python interpreter to use and export it as PYEXEC.
# This function is needed to support cross-compatibility of test infrastructure
# between RHEL-6/7 (python 2 distributions) and RHEL-8 (python 3 distribution
# with unusual python paths)
# Arguments :none
##
function RQA_set_pyexec {
    PYEXEC=''

    # first check if we have a python interpreter on the PATH
    if which python 1>/dev/null 2>&1; then
        export PYEXEC='python'
        return 0
    fi

    # if not, check for a python3 interpreter on the PATH
    if which python3 1>/dev/null 2>&1; then
        export PYEXEC='python3'
        return 0
    fi

    # if not, RHEL-8+ defaults to /usr/libexec/platform-python as the
    # default location for a python interpreter
    if which /usr/libexec/platform-python 1>/dev/null 2>&1; then
        export PYEXEC='/usr/libexec/platform-python'
        return 0
    fi

    # if we get here, python may not be installed; try installing various
    # pythons and searching again for a python interpreter on the PATH
    $PKGINSTALL --quiet --skip-broken python3 python2 python
    if which /usr/libexec/platform-python 1>/dev/null 2>&1; then
        PYEXEC='/usr/libexec/platform-python'
    elif which python3 1>/dev/null 2>&1; then
        PYEXEC='python3'
    elif which python2 1>/dev/null 2>&1; then
        PYEXEC='python2'
    elif which python 1>/dev/null 2>&1; then
        PYEXEC='python'
    fi

    if [ -n "$PYEXEC" ]; then
        # we found a python interpreter - use it
        export PYEXEC
    else
        # no python found in this distribution!
        echo "### WARNING: NO PYTHON INTERPRETER AVAILABLE ###"
        return 1
    fi
}

function RQA_install_packages() {
    # the very core packages available on all release
    $PKGINSTALL rdma-core libibverbs libibverbs-utils libibverbs-devel librdmacm librdmacm-utils librdmacm-devel perftest iperf3 infiniband-diags iscsi-initiator-utils
}

##
# Prints out some IB debug information
# Arguments: none
##
function RQA_system_info_for_debug {
    [ -f /etc/motd ] && grep -i distro /etc/motd | tr -d ' '
    [ -f /etc/redhat-release ] && cat /etc/redhat-release
    [ -f /etc//etc/fedora-release ] && cat /etc/fedora-release
    uname -a
    cat /proc/cmdline
    rpm -q rdma-core linux-firmware
    tail /sys/class/infiniband/*/fw_ver
    lspci | grep -i -e ConnectX -e omni -e FastLinQ -e NetXtreme-E -e e810 -e "Ethernet controller: Chelsio"
    lscpu
    ibstat
    ibstatus
    /usr/bin/ibv_devinfo -v
    ip addr show
}

# Arguments: service name and service action (order independent)
# Example: RQA_sys_service restart opensm
##
function RQA_sys_service {
    SERVICE_RETURN=1
    if [ $# -ne 2 ]; then
        echo "Pass two arguments - service_name & service action"
        return 1
    fi
    while test ${#} -gt 0; do
        case $1 in
            start|status|restart|stop|enable|disable|is-active|is-enabled)
                action=$1
                ;;
            *)
                serv=$1
                ;;
        esac
        shift
    done

    [ -f /lib/systemd/system/"$serv".service ] && systemctl $action $serv
    SERVICE_RETURN=$?

    serv=$(echo $serv | awk -F '.' '{print $1}')
    if [[ -f /etc/rc.d/init.d/$serv ]]; then
        case "$action" in
            "enable")
                # enable a service using chkconfig on
                /sbin/chkconfig $serv on
                ;;
            "disable")
                # disable a service using chkconfig off
                /sbin/chkconfig $serv off
                ;;
            "is-active")
                # similar to systemctl is-active, service status will
                # return 0 for an active service and 3 for inactive
                /sbin/service $serv status
                ;;
            "is-enabled")
                # to simulate systemctl is-enabled, use chkconfig to
                # check if the service is enabled at runlevel 3
                /sbin/chkconfig --list | grep $serv | grep "3:on"
                ;;
            *)
                # all other actions (start, status, restart, stop)
                # can be used directly by the service command
                /sbin/service $serv $action
                ;;
        esac
        SERVICE_RETURN=$?
    fi
}

# set the PYEXEC variable to a python interpreter scripts can use
RQA_set_pyexec

# determine whether to use yum or dnf
if [[ $(grep -iq fedora /etc/redhat-release) || $(RQA_get_rhel_major) -ge 8 ]]; then
    export PKGINSTALL="dnf install -y --setopt=strict=0 --nogpgcheck"
    export PKGREMOVE="dnf remove --noautoremove -y"
else
    export PKGINSTALL="yum install -y --skip-broken --nogpgcheck"
    export PKGREMOVE="yum remove -y"
fi

if RQA_exist_RDMA_HCA; then
    RQA_install_packages
fi
