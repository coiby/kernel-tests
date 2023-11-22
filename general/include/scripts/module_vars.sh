#!/bin/bash
# This file contains the shared variables used in various kmod/DUP/ftrace tests

DistVer=`rpm -E '%{?dist}' | sed 's/[^0-9]//g'`
KVer=`uname -r | awk -F '-' '{print $1}'`
KDIST=`uname -r | sed "s/.$(arch)//g;s/\+debug//g;s/\.debug//g" | awk -F '.' '{print "."$NF}'`
KBUILD=`uname -r | awk -F '-' '{print $2}' | sed "s/.$(arch)//g;s/\+debug//g;s/\.debug//g" | sed "s/${KDIST}//g"`
KBUILDPrefix=`echo ${KBUILD} | awk -F '.' '{print $1}'`
if [ "${KVer}" == "4.11.0" ] && [ "${KBUILDPrefix}" -le "9" ] && [ "${KDIST}" == ".el7a" ] ;
then
    KDIST=".el7"
fi

KSRPMNAME=${KSRPMNAME:-$(rpm -q --queryformat '%{sourcerpm}\n' -qf /boot/config-$(uname -r) | sed "s/.srpm//g;s/.src.rpm//g;s/-${KVer}-${KBUILD}${KDIST}//g")}
currentvariant=`rpm -qf /boot/config-$(uname -r) | sed "s/.srpm//g;s/.src.rpm//g;s/.rpm//g;s/-${KVer}-${KBUILD}${KDIST}.$(arch)//g;s/^kernel//g;s/-core$//g"`

KVARIANT=${KVARIANT:-${currentvariant}}
BREWPKGS="http://download.devel.redhat.com/brewroot/packages/"
SERVERPREFIX=${downloadfrom:-${BREWPKGS}}

# This is for common install scripts
# You can use like
# yum=$(select_yum_tool)
# Currently this is used by ebpf-tracing tests
function select_yum_tool() {
    if [ -x /usr/bin/dnf ]; then
        echo "/usr/bin/dnf"
    elif [ -x /usr/bin/yum ]; then
        echo "/usr/bin/yum"
    else
        return 1
    fi

    return 0
}

yum=$(select_yum_tool)

# Scratch is usually available in like http://brew-task-repos.usersys.redhat.com/repos/scratch/zsun/kernel/4.18.0/32.el8.2.2/x86_64/kernel-4.18.0-32.el8.2.2.src.rpm
# Override downloadfrom from task parameters if need to test scratch

install_kernel_dev_dependency()
{
    for i in asciidoc audit-libs audit-libs-devel binutils-devel bison bzip2 createrepo elfutils elfutils-devel elfutils-libelf-devel gcc gcc-c++ genisoimage git glibc-static libcap-devel libgcc newt-devel nfs-utils numactl-devel openssl-devel patchutils pciutils-devel perl perl-ExtUtils-Embed pesign python2-tools python-devel rpm-build util-linux wget xmlto yum-utils zlib-devel bc openssl readline-devel python3-docutils; do
        $yum install -y -q $i
    done
    if rlIsRHEL 7; then
        for i in python-devel python-setuptools kernel-abi-whitelists; do
            $yum install -y -q $i
        done
    fi
    if rlIsRHEL 8; then
        for i in platform-python-devel dwarves kernel-abi-whitelists; do
            $yum install -y -q $i
        done
    fi
    if rlIsRHEL 9; then
        for i in kernel-abi-stablelists python3-devel; do
            $yum install -y -q $i
        done
    fi
    if [[ ${DistVer} -lt 7 ]]; then
        $yum install -y -q module-init-tools
    else
        $yum install -y -q kmod
    fi
}

# download_kernel_subpackages is mainly use to sync perf / kernel-devel / kernel-debuginfo etc.
# Install kernel might be supported but no guarantee.
install_kernel_subpackages()
{
    # Workaround of extra existing *debuginfo packages
    if [[ ${KVARIANT} != *"-debug"* ]]; then
        $yum remove -y -q kernel-debug-debuginfo*
        $yum remove -y -q perf-debuginfo*
    fi
    KBuild=${KBuild:-${KBUILD}}
    kernel_vra="${KVer}-${KBuild}${KDIST}.$(arch)"
    allyumrpm=""
    allpkgurl=""
    if [[ ${DistVer} -lt 9 ]]; then
        # the KPKGS should always have kernel-debuginfo before perf-debuginfo to make sure corresponding kernel*-debuginfo-common* is already installed
        KPKGS="kernel-debuginfo kernel-headers kernel-abi-whitelists perf perf-debuginfo bpftool kernel-devel"
    else
        KPKGS="kernel-debuginfo kernel-headers kernel-abi-stablelists perf perf-debuginfo bpftool kernel-devel"
    fi
    for p in $KPKGS ; do
        pkgurl=""
        yumrpm=""
        case "$p" in
            kernel-debuginfo)
                yumrpm="kernel${KVARIANT}-debuginfo-${kernel_vra} $(echo $KSRPMNAME | sed 's/-alt//g;')-debuginfo-common-$(arch)-${kernel_vra}"
                pkgurl="${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/kernel${KVARIANT}-debuginfo-${kernel_vra}.rpm ${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/$(echo $KSRPMNAME | sed 's/-alt//g;')-debuginfo-common-$(arch)-${kernel_vra}.rpm"
                ;;
            kernel)
                if [[ ${DistVer} -gt 7 ]]; then
                    yumrpm="kernel${KVARIANT}-core-${kernel_vra} kernel${KVARIANT}-modules-${kernel_vra}"
                    pkgurl="${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/kernel${KVARIANT}-core-${kernel_vra}.rpm ${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/kernel${KVARIANT}-modules-${kernel_vra}.rpm"
                else
                    yumrpm="kernel${KVARIANT}-${kernel_vra}"
                    pkgurl="${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/${yumrpm}.rpm"
                fi
                ;;
            kernel-devel)
                yumrpm="kernel${KVARIANT}-devel-${kernel_vra}"
                pkgurl="${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/${yumrpm}.rpm"
                ;;
            perf-debuginfo)
                if [[ $KBuild == *"rt"* ]]; then
                    stockbuild=$(echo ${KBuild} | awk 'NF{NF-=2}1' FS='.' OFS='.')
                    yumrpm="$p-${KVer}-${stockbuild}${KDIST} kernel-debuginfo-common-$(arch)-${KVer}-${stockbuild}${KDIST} kernel-debuginfo-${KVer}-${stockbuild}${KDIST}"
                    pkgurl="${SERVERPREFIX}/kernel/${KVer}/${stockbuild}${KDIST}/$(arch)/$p-${KVer}-${stockbuild}${KDIST}.$(arch).rpm ${SERVERPREFIX}/kernel/${KVer}/${stockbuild}${KDIST}/$(arch)/kernel-debuginfo-common-$(arch)-${KVer}-${stockbuild}${KDIST}.$(arch).rpm ${SERVERPREFIX}/kernel/${KVer}/${stockbuild}${KDIST}/$(arch)/kernel-debuginfo-${KVer}-${stockbuild}${KDIST}.$(arch).rpm"
                else
                    yumrpm="$p-${kernel_vra} $(echo $KSRPMNAME | sed 's/-alt//g;')-debuginfo-common-$(arch)-${kernel_vra} $(echo $KSRPMNAME | sed 's/-alt//g;')-debuginfo-${kernel_vra}"
                    pkgurl="${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/$p-${kernel_vra}.rpm ${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/$(echo $KSRPMNAME | sed 's/-alt//g;')-debuginfo-common-$(arch)-${kernel_vra}.rpm ${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/$(arch)/$(echo $KSRPMNAME | sed 's/-alt//g;')-debuginfo-${kernel_vra}.rpm"
                    # Remove existing userspace to make this work with install old kernel onto new distro scenario
                    rpm -q ${yumrpm} || yum remove -y -q $p
                fi
                ;;
            *)
                pkgarch=$(arch)
                if [[ $p == *"kernel-abi-whitelists"* ]] || [[ $p == *"kernel-abi-stablelists"* ]] || [[ $p == *"kernel-doc"* ]] || [[ $p == *"firmware"* ]]; then
                    pkgarch="noarch"
                fi
                if [[ $KBuild == *"rt"* ]] && [[ $p != *"kernel"* ]]; then
                    yumrpm="$p-${KVer}-$(echo ${KBuild} | awk 'NF{NF-=2}1' FS='.' OFS='.')${KDIST}"
                    pkgurl="${SERVERPREFIX}/kernel/${KVer}/$(echo ${KBuild} | awk 'NF{NF-=2}1' FS='.' OFS='.')${KDIST}/${pkgarch}/${yumrpm}.${pkgarch}.rpm"
                else
                    yumrpm="$p-${KVer}-${KBuild}${KDIST}.${pkgarch}"
                    pkgurl="${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/${pkgarch}/${yumrpm}.rpm"
                    # Remove existing userspace to make this work with install old kernel onto new distro scenario
                    rpm -q ${yumrpm} || yum remove -y -q $p
                fi
                ;;
        esac
        allyumrpm+=" ${yumrpm} "
        allpkgurl+=" ${pkgurl} "
        # $yum install -y ${yumrpm} || yum install -y $pkgurl || rpm -q ${yumrpm} || yum install -y $p
        #rpm -q ${yumrpm} || $yum install -y ${yumrpm}.rpm || rpm -q ${yumrpm} || yum install -y $p
        echo $pkgurl
    done

    rm -rf "/mnt/testarea/${KBuild}${KDIST}"
    mkdir -p "/mnt/testarea/${KBuild}${KDIST}"
    pushd /mnt/testarea/${KBuild}${KDIST}/

    # Add task param, needed for kernel-ci/CKI, e.g. <params><param name="CI" value="yes"/><params>
    if [ "$CI" == "yes" ]; then
        for a in $allyumrpm ; do
            if rlIsRHEL 7; then
                yumdownloader ${a}
            else
                $yum download ${a}
            fi
        done
    else
        for a in $allpkgurl ; do
            wget -nv $a
        done
    fi
    $yum install -y -q createrepo
    createrepo .
    rm /etc/yum.repos.d/sub-pkgs.repo -f
    cat > /etc/yum.repos.d/sub-pkgs.repo <<EOREPO
[sub-pkgs]
name=sub-pkgs
baseurl=file://$(pwd)
gpgcheck=0
enable=1
skip_if_unavailable=True
EOREPO
    yum install -y --skip-broken $allyumrpm
    for p in $allyumrpm ; do
        yum install -y --skip-broken $p
    done
    echo "== Install result: =="
    rpm -qa | grep ${KVer}-${KBuild}
    echo "---------------------"
    rpm -q ${KPKGS} kernel-debuginfo-common-$(arch)
    echo "===================="
    popd
}
install_kernel_srpm()
{

    KBuild=${KBuild:-${KBUILD}}
    KSRPM="${SERVERPREFIX}/${KSRPMNAME}/${KVer}/${KBuild}${KDIST}/src/${KSRPMNAME}-${KVer}-${KBuild}${KDIST}.src.rpm"

    if [ "$CI" == "yes" ]; then
        if rlIsRHEL 7; then
            yumdownloader --source kernel-${KVer}-${KBuild}${KDIST}
        else
            $yum download kernel-${KVer}-${KBuild}${KDIST} --source
        fi
    else
        rlRpmDownload --source ${KSRPMNAME}-${KVer}-${KBuild}${KDIST} || wget ${KSRPM}
    fi
    rpm -ivh --force ${KSRPMNAME}-${KVer}-${KBuild}${KDIST}.src.rpm
    $yum builddep -y ~/rpmbuild/SPECS/kernel.spec
}

$yum install -y -q wget

if [ "$SYNCSUBPKGS" == "yes" ]; then
    install_kernel_subpackages
fi
if [ "$DEVTOOLS" == "yes" ]; then
    install_kernel_dev_dependency
fi
if [ "$SYNCSRPM" == "yes" ]; then
    install_kernel_srpm
fi
