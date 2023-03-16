#!/bin/bash

# install fwts with efi_runtime under current rhivos images will
# met error
# - SSL error:FFFFFFFF80000002:system library::No such file or directory: crypto/bio/bss_file.c:67
# - SSL error:10000080:BIO routines::no such file: crypto/bio/bss_file.c:75

. /usr/share/beakerlib/beakerlib.sh || exit 1

: ${DeBug:=0} # Set to non-zero value to enable debugging

OSARCH="$(uname -m)"
KVER="$(uname -r)"
YUM="rpm-ostree -A -y --allow-inactive"
FWTS_VERSION=${FWTS_VERSION:-V23.01.00}
FWTS_GIT_REMOTE="https://git.launchpad.net/fwts"
FWTS_DEP_PKGS="autoconf automake libtool flex flex-devel bison dkms libfdt libfdt-devel dtc pcre-devel pcre2 pcre2-devel pcre2-utf16 pcre2-utf32 glib2 glib2-devel pciutils pciutils-devel zlib-devel make libbsd-devel kernel-devel kernel-automotive-devel-$KVER"



EPEL9_PKG=https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

function fwtsSetupRepos()
{   
    rlLog "setup EPEL9 repo"
    rlRun "$YUM install $EPEL9_PKG" 0 "install epel repo"

    rlLog "setup interal repo"
    cat >/etc/yum.repos.d/rhel9-inside.repo <<EOF
[baseos]
name=RHEL9 for $OSARCH - Base
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/BaseOS/$OSARCH/os/
enabled=1
gpgcheck=0

[appstream]
name=RHEL9 for $OSARCH - AppStream
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/AppStream/$OSARCH/os/
enabled=1
gpgcheck=0

[codeready-builder-for-rhel-9]
name=RHEL9 for $OSARCH - CodeReady Builder
baseurl=http://download.eng.brq.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/CRB/$OSARCH/os/
enabled=1
EOF
    cat >/etc/yum.repos.d/rhivos.repo <<EOF
[rhivos-external]
name=RHIVOS - base - outside
baseurl=https://buildlogs.centos.org/9-stream/automotive/$OSARCH/packages-main/
enabled=1
gpgcheck=0

[rhivos-autosd-external]
name=RHIVOS - autosd - outside
baseurl=https://buildlogs.centos.org/9-stream/autosd/$OSARCH/packages-main/
enabled=1
gpgcheck=0
EOF
}

function fwtsPreSetup()
{
    rlRun "$YUM install $FWTS_DEP_PKGS" 0 "install fwts dep packages"
    rlRun "git clone $FWTS_GIT_REMOTE" 0 "get fwts source code"
    rlRun "cd fwts" 0 "cd into fwts source directory"
    rlRun "git checkout -b $FWTS_VERSION" 0 "checkout latest"
}

function fwtsBuild()
{   
    # build efi_runtime
    # need mount fs to rw, otherwise install kmod will fail
    rlLog "mount /usr as rw to install kmod"
    rlRun "mount -o remount,rw /dev/vda3 /usr" 0 "remount /usr to rw"

    rlRun "pushd efi_runtime"
    rlRun "KVER=$KVER make all install" 0 "build efi_runtime kmod"
    rlRun "popd"
    
    # build fwts
    rlLog "start building fwts"
    rlRun "autoreconf -ivf" 0 "autoreconf"
    rlRun "./configure" 0 "configure"
    rlRun "make" 0 "start building fwts from source"
    rlRun "make install" 0 "install fwts binary"
}

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