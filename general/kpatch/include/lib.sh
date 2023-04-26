#!/usr/bin/bash

BUILDS_URL="${BUILDS_URL:-}"
PACKAGE=kpatch
SERVICE=kpatch
kpackage=$(rpm -qf /boot/config-`uname -r` | sed "s/.`uname -i`//g; s/core-//g;")
karch=$(rpm -q $kpackage --qf "%{arch}")
knam=$(rpm -q $kpackage --qf "%{name}")
kver=$(rpm -q $kpackage --qf "%{version}")
krel=$(rpm -q $kpackage --qf "%{release}")

dnf_install_modules_internal()
{
    dnf install -q -y ${knam}-modules-internal-${kver}-${krel} \
        || yum install -q -y ${BUILDS_URL}/${knam}/${kver}/${krel}/${karch}/${knam}-modules-internal-${kver}-${krel}.${karch}.rpm
}
