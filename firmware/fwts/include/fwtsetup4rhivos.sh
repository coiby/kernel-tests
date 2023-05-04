#!/bin/bash

# install fwts with efi_runtime under current rhivos images will
# met error
# - SSL error:FFFFFFFF80000002:system library::No such file or directory: crypto/bio/bss_file.c:67
# - SSL error:10000080:BIO routines::no such file: crypto/bio/bss_file.c:75

function fwtsSetup()
{
    OSARCH="$(uname -m)"
    KVER="$(uname -r)"
    YUM="rpm-ostree -y --apply-live --allow-inactive"
    FWTS_VERSION=${FWTS_VERSION:-V23.03.00}
    FWTS_GIT_REMOTE="https://git.launchpad.net/fwts"
    FWTS_DEP_PKGS="acpica-tools glib2-devel json-c-devel libtool automake autoconf dkms git bison flex kernel-devel kernel-automotive-devel-$KVER"
    EPEL9_PKG=https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

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
gpgcheck=0

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


    rlRun "$YUM install $FWTS_DEP_PKGS" 0 "install fwts dep packages"
    rlRun "git clone $FWTS_GIT_REMOTE" 0 "get fwts source code"
    rlRun "cd fwts" 0 "cd into fwts source directory"
    rlRun "git checkout -b $FWTS_VERSION" 0 "checkout latest"


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
