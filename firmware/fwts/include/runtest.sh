#!/bin/bash

. ../../../cki_lib/libcki.sh
# Include rhts environment
if ! cki_is_kernel_automotive; then
    . /usr/bin/rhts-environment.sh || exit 1
fi

. /usr/share/beakerlib/beakerlib.sh || exit 1

# Task parameters
# DeBug - Set to non-zero value to enable debugging
# FwtsTarBall - name of tarball to use
# FwtsTarBallUrl - url of the tarball, defaults to $LOOKASIDE/$FwtsTarBall
# FwtsGitRemote - git repository, defaults to "http://github.com/fwts/fwts.git"
# FwtsGitBranch - git branch that will be used


: ${DeBug:=0} # Set to non-zero value to enable debugging
FwtsIncludeDir=$(readlink -f "../include/")

LOOKASIDE=${LOOKASIDE:-http://download.devel.redhat.com/qa/rhts/lookaside/}
FWTS_ON_FAIL_REPORT=${FWTS_ON_FAIL_REPORT:-FAIL}
FWTS_VERSION=${FWTS_VERSION:-V23.09.00}


if [ -n "$FwtsGitRemote" -o -n "$FwtsGitBranch" ]; then
    : ${FwtsGitRemote:=https://github.com/fwts/fwts.git}
    : ${FwtsGitBranch:=$FWTS_VERSION}
else
    : ${FwtsTarBall:=fwts-$FWTS_VERSION.tar.gz}
    : ${FwtsTarBallUrl:=$LOOKASIDE/$FwtsTarBall}
fi


function fwtsSetup()
{
    # Setup build prerequisites for fwts
    # normally Beaker pre-installs the prereqs, but since this is an "include"
    # task Beaker won't check the rpm-requirements for this task

    # This is for issue "gcc: fatal error: Killed signal terminated program cc1"
    if cki_is_kernel_automotive; then
        rlRun "fallocate -l 1G swapfile && \
               chmod 600 swapfile && \
               mkswap swapfile && \
               swapon swapfile && \
               echo 'swapfile swap swap defaults 0 0' >> /etc/fstab" 0 "create swap memory"
    fi

    if ! rlCheckRpm pcre-devel; then
        if ! cki_is_kernel_automotive; then
            yum install pcre-devel -y
        else
cat >/etc/yum.repos.d/rhel.repo <<EOF
[baseos-rhel]
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/BaseOS/$(arch)/os
enabled=1
gpgcheck=0
[appstream-rhel]
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/AppStream/$(arch)/os/
enabled=1
gpgcheck=0
[crb-rhel]
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/CRB/$(arch)/os/
enabled=1
gpgcheck=0
[baseos-debug-rhel]
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/BaseOS/$(arch)/debug/tree
enabled=1
gpgcheck=0
[appstream-debug-rhel]
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/AppStream/$(arch)/debug/tree
enabled=1
gpgcheck=0
[crb-debug-rhel]
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/CRB/$(arch)/debug/tree
enabled=1
gpgcheck=0
EOF
            rpm-ostree install --assumeyes --apply-live --idempotent --allow-inactive pcre-devel
        fi
        rlAssertRpm pcre-devel
    fi

    if ! rlCheckRpm json-c-devel; then
        if ! cki_is_kernel_automotive; then
            yum install json-c-devel -y
        else
            rpm-ostree install --assumeyes --apply-live --idempotent --allow-inactive json-c-devel
        fi
        rlAssertRpm json-c-devel
    fi

    if ! rlCheckRpm glib2-devel; then
        if ! cki_is_kernel_automotive; then
            yum install glib2-devel -y
        else
            rpm-ostree install --assumeyes --apply-live  --idempotent --allow-inactive glib2-devel
        fi
        rlAssertRpm glib2-devel
    fi

    if ! rlCheckRpm elfutils-libelf-devel; then
        if ! cki_is_kernel_automotive; then
            yum install elfutils-libelf-devel -y
        else
            rpm-ostree install --assumeyes --apply-live  --idempotent --allow-inactive elfutils-libelf-devel
        fi
        rlAssertRpm elfutils-libelf-devel
    fi

    local k_name=$(rpm --queryformat '%{name}\n' -qf /boot/config-$(uname -r) | sed -e 's/-core//')

    if ! rlCheckRpm ${k_name}-devel $(uname -r); then
        if ! cki_is_kernel_automotive; then
            yum install ${k_name}-$(uname -r) -y
        else
cat > /etc/yum.repos.d/rhivos-outside.repo <<EOF
[rhivos-external]
name=RHIVOS - base - outside
baseurl=https://buildlogs.centos.org/9-stream/automotive/$(arch)/packages-main/
enabled=1
gpgcheck=0

[rhivos-autosd-external]
name=RHIVOS - autosd - outside
baseurl=https://buildlogs.centos.org/9-stream/autosd/$(arch)/packages-main/
enabled=1
gpgcheck=0
EOF
             rpm-ostree install --assumeyes --apply-live --idempotent --allow-inactive "${k_name}-devel-$(uname -r)"
        fi
        rlAssertRpm ${k_name}-devel-$(uname -r)
    fi

    # libbsd is a requirement to build.
    # It is only available in EPEL.
    # To avoid adding the entire EPEL or depending on it, just pull these RPMs which should be fine
    if ! rlCheckRpm libbsd-devel; then
cat >/etc/yum.repos.d/libbsd.repo <<EOF
[libbsd]
name=libbsd
baseurl=http://download.devel.redhat.com/qa/rhts/lookaside/fwts-deps/libbsd/
enabled=1
gpgcheck=0
EOF
        if ! cki_is_kernel_automotive; then
            yum install libbsd-devel -y
        else
            rpm-ostree install --assumeyes --apply-live --idempotent --allow-inactive "libbsd-devel"
        fi
        rlAssertRpm libbsd-devel
    fi

    #Some packages only need for rhivos
    if cki_is_kernel_automotive; then
        if ! rlCheckRpm patch; then
            rpm-ostree install --assumeyes --apply-live  --idempotent --allow-inactive patch
            rlAssertRpm patch
        fi

        if ! rlCheckRpm autoconf; then
            rpm-ostree install --assumeyes --apply-live  --idempotent --allow-inactive autoconf
            rlAssertRpm autoconf
        fi

        if ! rlCheckRpm automake; then
            rpm-ostree install --assumeyes --apply-live  --idempotent --allow-inactive automake
            rlAssertRpm automake
        fi

        if ! rlCheckRpm libtool; then
            rpm-ostree install --assumeyes --apply-live  --idempotent --allow-inactive libtool
            rlAssertRpm libtool
        fi
    fi

    # Skip download/build/installation if it looks like fwts is already installed
    if ! [ -x /usr/local/bin/fwts ] ; then

        # Download fwts sources
        rlRun "TmpDir=\`mktemp -d\`" 0 "Creating tmp directory"
        rlRun "cd $TmpDir" 0 "change directory to tmpdir"
        if [ -n "$FwtsGitRemote" ]; then
            # Get sources from git
            if [ -n "$FwtsGitBranch" -a "$FwtsGitBranch" != "HEAD" ]; then
                rlRun "git clone --branch $FwtsGitBranch $FwtsGitRemote" 0 "clone git repository"
            else
                rlRun "git clone $FwtsGitRemote" 0 "clone git repository"
            fi
            rlRun "cd fwts" 0 "cd into fwts source directory"
            rlLog "Current branch is $(git rev-parse --abbrev-ref HEAD) $(git rev-parse HEAD)"
        else
            # Get sources from tarball
            local wget_opts="-Nnv"
            rlRun "wget $wget_opts -O $FwtsTarBall $FwtsTarBallUrl" 0 "download fwts tarball"
            rlRun "mkdir fwts" 0 "create fwts directory for build" # latest tarballs don't have a top fwts dir
            rlRun "tar -xf $FwtsTarBall -C fwts" 0 "untar tarball"
            rlRun "cd fwts" 0 "cd into fwts source directory"
        fi

        # Apply patches
        for p in ${FwtsIncludeDir}/patches/*.patch ; do
            rlRun "patch -p1 < $p" 0 "applying $p"
        done

        # setup efi_runtime module needed by uefirt* tests
        # make modules_install so efi_runtime can be loaded with modprobe as fwts requires
        rlRun "cd efi_runtime" 0 "cd into efi_runtime directory"

        # remount /usr folder as rw access promission
        if cki_is_kernel_automotive; then
            rlRun "sudo mount -o remount,rw /dev/vda3 /usr" 0 "remount /usr to rw access promission"
        fi

        # Setting $KVER to the running kernel version should negate the need for  0003-efi_runtime_Makefile_modules_install.patch
        if [ "$(uname -m)" = "aarch64" ] ; then
            rlRun "ARCH=arm64 KVER=$(uname -r) make all install" 0 "make all install inside efi_runtime"
        else
            rlRun "KVER=$(uname -r) make all install" 0 "make all install inside efi_runtime"
        fi
        rlRun "cd .." 0 "cd up one directory back into fwts source root"

        # run autoreconf to recreate build system files for fwts
        rlRun "autoreconf -ivf" 0 "run autoreconf to recreate build system files for fwts"

        # run configure script to generage Makefile for fwts
        rlRun "./configure" 0 "run configure to generate Makefile for fwts"

        # run make to build binaries from source for fwts
        rlRun "make -j$(nproc)" 0 "run make to build binaries from source for fwts"

        # run make install to install files for fwts on system
        rlRun "make install" 0 "run make install to install files for fwts on system"
    else
        rlLog "It appears that fwts is already installed, skipping the build process"
    fi # endif for install check
    # Get fwts version from installed fwts binary
    rlRun -l "fwts -v" 0 "run fwts to get version, if this fails fwts likely did not build/install properly"

    # Run modinfo on efi_runtime to confirm it installed properly
    rlRun -l "modinfo efi_runtime" 0 "Check to see if efi_runtime built/installed properly"
}

if cki_is_kernel_automotive; then
    . ../include/fwtsetup4rhivos.sh
fi

function fwtsReportResults()
{
    rlPhaseStartTest "Results"
    # first, submit fwts results.log file to beaker
    rlAssertExists "results.log"
    rlFileSubmit "results.log"

    if [[ "$FWTS_SKIP_REPORT" == "1" || "$FWTS_ON_FAIL_REPORT" == "PASS" ]]; then
            rlPhaseEnd
            return
    fi

    resultSummaryLines=$(cat results.log | awk '/^---------------\+-----\+-----\+-----\+-----\+-----\+-----\+/ { print FNR }')
    echo $resultSummaryLines

    beginTableLine=$(echo $resultSummaryLines | awk '{print $1}')
    endTableLine=$(echo $resultSummaryLines | awk '{print $2}')

    # there is a third summary line after the totals FYI

    # Throw away the beginning and end of table
    beginTableLine=$(( $beginTableLine + 1 ))
    endTableLine=$(( $endTableLine - 1 ))

    sed -n $beginTableLine\,$endTableLine\p results.log > resultsSummary.out

    while IFS= read -r line
    do
        fwtsTest=$(echo "$line" | awk -F \| '{print $1}')
        fwtsTest=$(echo $fwtsTest) # trim trailing whitespaces
        fwtsFail=$(echo "$line" | awk -F \| '{print $3}')
        fwtsFail=$(echo $fwtsFail) # trim trailing whitespaces

        ignoretest=0
        for ignore in $FWTS_IGNORE_LIST
        do
                if  [[ "$ignore" == "$fwtsTest" ]]; then
                        ignoretest=1
                        break
                fi
        done

        if  [ $ignoretest == 1 ]; then
                echo "$fwtsTest in ignorelist, ignoring results."
                continue
        fi

        if [[ "$fwtsFail" -gt 0 ]]
        then
                rlFail "$fwtsTest"
        fi
    done < resultsSummary.out
    rlPhaseEnd
}

function fwtsCleanup()
{
    if [ -d "$TmpDir" ] ; then
        [[ $DeBug = "0" ]] && rlRun "rm -r $TmpDir" 0 "Removing tmp directory" || rlLog "Debugging enabled, keeping $TmpDir"
    fi
}
