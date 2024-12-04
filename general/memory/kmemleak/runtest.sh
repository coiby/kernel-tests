#!/bin/bash
# shellcheck disable=SC2002,SC2181,SC2015,SC2153
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Wang Shu <shuwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1


export LEAKFILE='/sys/kernel/debug/kmemleak'
export LEAKREPORT=$(pwd)/kmemleak
export LEAKREPORT_OLD=$(pwd)/kmemleak_old

# upload leak file to kg server
LEAKUPLOAD=${LEAKUPLOAD:-'yes'}

INSTALLPATH='/mnt/tests/kernel/distribution/upstream-kernel/install/'

# upstream kernel build required variables
export CUSTOM_KCONFIG='CONFIG_DEBUG_KMEMLEAK=y CONFIG_DEBUG_KMEMLEAK_DEFAULT_OFF=n DEBUG_KMEMLEAK_EARLY_LOG_SIZE=4000'
export KERNEL_GIT_COMMIT=${KERNEL_GIT_COMMIT:-'HEAD'}
export USE_GIT_CLONE=1

# install kernel rpm package
KERNURL=${KERNURL:-''}

# kmemleak target kernel
KERNTARGET=${KERNTARGET:-'debugkernel'}



function report_leak()
{
    local l1;
    local l2;

    if [ ! -f "${LEAKREPORT}" ]; then
        touch "$LEAKREPORT" "$LEAKREPORT_OLD"
    fi
    # shellcheck disable=SC2009
    ps -C kmemleak -o pid,state,start_time,etime,args | grep kmemleak

    rlRun -l "echo scan > ${LEAKFILE}" 0-255
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        rstrnt-report-result "skip_scan_stopped" SKIP
    fi

    sleep 10        # wait a few secs for leak happens
    rlRun "cat ${LEAKFILE} > ${LEAKREPORT}" 0-255

    l1=$(cat "${LEAKREPORT}" | wc -l)
    l2=$(cat "${LEAKREPORT_OLD}" | wc -l)
    if [ "${l1}" == "${l2}" ]; then
        echo "Didn't change in $LEAKFILE, saying no new leak in test $TEST"
        return;
    fi

    [ "$l2" = 0 ] && echo "Find new leak in test $TEST"

    if [ "${l1}" = "0" ]; then
        echo "$LEAKFILE become empty after running $TEST, saying it was false positive for the previous leak"
        return;
    fi

    rstrnt-report-result  "$TEST/kmemleak" WARN
    rstrnt-report-log -l "$LEAKREPORT"
    cat "${LEAKFILE}" > "${LEAKREPORT_OLD}"

    if [ "${LEAKUPLOAD}" != "yes" ]; then
        return
    fi

    local kinfo;
    local submitter="${SUBMITTER/@*/}${SUBMITTER:+-}"
    local jobid="${JOBID}${JOBID:+-}"
    local recipeid="${RECIPEID}${RECIPEID:+-}"
    kinfo=$(uname -r |cut -d. -f1,2,3 |sed 's/\./_/g')
    if [ -f "./gitinfo" ]; then
        kinfo="$(cat ./gitinfo)"
    fi
    local leakname=${submitter}${jobid}${recipeid}$(uname -m)-${kinfo}.kmemleak

    /usr/bin/expect <<EOF
set timeout -1
spawn scp ${LEAKREPORT} ${KG_SERVER_USER}@vmcore.usersys.redhat.com:/data/kgqe/kmemleak/$leakname
expect {
"*yes/no" { send "yes\r"; exp_continue }
"*password:" { send "redhat\r"; exp_continue }
}
expect eof.
EOF

}


function install_debugkernel()
{
    if grep -w 1 /mnt/DK_INSTALL; then
        rlRun "grep kmemleak=on /proc/cmdline"
        uname -r | grep '+debug$' || rlDie "not debug kernel running $(uname -r)"
        rlReport "$(uname -r)" PASS
        echo 2 > /mnt/DK_INSTALL
        return
    elif grep -w 2 /mnt/DK_INSTALL; then
        return
    elif grep -w 3 /mnt/DK_INSTALL; then
        rlRun "grep kmemleak=on /proc/cmdline" 1-255 "cleanup cmdline"
        return
    fi

    WGET_KERNEL="../../include/scripts/wget-kernel.sh"

    # Remove the +deubg and .arch tail.
    local ver_rel=$(uname -r | sed 's/.'$(uname -m).*$'//')
    local kernelpath
    if ! uname -r | grep '+debug$'; then
        rlRun "$WGET_KERNEL --nvr $ver_rel --debugkernel -i"
        [ $? = 0 ] && kernelpath=$(ls /boot/vmlinuz-"${ver_rel}".$(uname -m)+debug) || \
        # This is a fallback debug kernel, just in case wget-kernel failed.
        { rlRun "yum install -y kernel-debug"; kernelpath=$(ls /boot/vmlinuz-*debug); }
    else
        kernelpath=$(ls /boot/vmlinuz-"${ver_rel}".$(uname -m)+debug)
    fi

    test -z "$kernelpath" && rlDie "no debug vmlinuz path defined!"

    rlRun "grubby --args='kmemleak=on' --update-kernel=ALL"
    rlRun "grubby --args='nokaslr' --update-kernel=ALL"
    uname -r | grep -q s390x && zipl
    rlRun "grubby --set-default=$kernelpath"
    uname -r | grep -q s390x && zipl
    rlPhaseEnd

    echo 1 > /mnt/DK_INSTALL
    rstrnt-reboot
}

function install_upstream()
{
    if grep -w 1 /mnt/DK_INSTALL; then
        rlRun "grep kmemleak=on /proc/cmdline"
        uname -r | grep '+debug$' || rlLogError "debug kernel running?"
        rlReport "$(uname -r)" PASS
        echo 2 > /mnt/DK_INSTALL
        return
    elif grep -w 2 /mnt/DK_INSTALL; then
        return
    elif grep -w 3 /mnt/DK_INSTALL; then
        rlRun "grep kmemleak=on /proc/cmdline" 1-255 "cleanup cmdline"
        return
    fi

    local gitinfo;
    yum install -y numactl numactl-devel openssl-devel libelf-dev libelf-devel elfutils-libelf-devel
    yum install -y kernel-kernel-distribution-upstream-kernel-install

    pushd $INSTALLPATH
    make run
    pushd ./kernel
    gitinfo=$(git describe)
    rstrnt-report-result  "$TEST/$gitinfo" PASS
    popd
    popd
    echo "$gitinfo" > ./gitinfo
    rlPhaseEnd

    echo 1 > /mnt/DK_INSTALL
    rstrnt-reboot
}


function install_kernelurl()
{
    if [ -z "$KERNURL" ] && [ "$KERNTARGET" = "rpm" ]; then
        echo "KERNURL is not provided!"
        exit 1
    fi
    if grep -w 1 /mnt/DK_INSTALL; then
        rlRun "grep kmemleak=on /proc/cmdline"
        uname -r | grep '+debug$' || rlLogError "debug kernel running?"
        rlReport "$(uname -r)" PASS
        echo 2 > /mnt/DK_INSTALL
        return
    elif grep -w 2 /mnt/DK_INSTALL; then
        return
    elif grep -w 3 /mnt/DK_INSTALL; then
        rlRun "grep kmemleak=on /proc/cmdline" 1-255 "cleanup cmdline"
        return
    fi

    rlRun "wget $KERNURL"

    local rpmname=$(basename "$KERNURL")
    rlRun "yum install -y ./${rpmname}"
    local kernelpath=$(rpm -pql ./"${rpmname}" | grep '/boot/vmlinuz')

    rlRun "grubby --args='kmemleak=on' --update-kernel=ALL"
    rlRun "grubby --args='nokaslr' --update-kernel=ALL"
    uname -r | grep -q s390x && zipl
    rlRun "grubby --set-default=$kernelpath"
    uname -r | grep -q s390x && zipl
    rlPhaseEnd

    echo 1 > /mnt/DK_INSTALL
    rstrnt-reboot
}

function install_brew_or_other()
{
    if grep -w 1 /mnt/DK_INSTALL; then
        rlRun "grep kmemleak=on /proc/cmdline"
        uname -r | grep '+debug$' || rlLogError "debug kernel running?"
        rlReport "$(uname -r)" PASS
        echo 2 > /mnt/DK_INSTALL
        return
    elif grep -w 2 /mnt/DK_INSTALL; then
        true
    elif grep -w 3 /mnt/DK_INSTALL; then
        rlRun "grep kmemleak=on /proc/cmdline" 1-255 "cleanup cmdline"
    else
        # for brew build
        echo 1 > /mnt/DK_INSTALL
        rstrnt-reboot
    fi
}

function hack_reboot()
{
    if grep -q kmemleakreport /usr/bin/rstrnt-reboot; then
        rlRun "echo rstrnt-reboot has already been hacked"
        return 0;
    fi

    cat > /usr/bin/kmemleakreport.sh <<EOF
if test -f "${LEAKFILE}" && test -f "${LEAKREPORT}" && test -f "${LEAKREPORT_OLD}"; then
    echo scan > ${LEAKFILE}
    cat ${LEAKFILE} > ${LEAKREPORT}
    l1=\$(cat ${LEAKREPORT} | wc -l)
    l2=\$(cat ${LEAKREPORT_OLD} | wc -l)
    if [ "\${l1}" == "\${l2}" ]; then
        exit 0
    fi
    rstrnt-report-result  $TEST/kmemleak.before_reboot WARN
    rstrnt-report-log -l $LEAKREPORT
    cat /dev/null > ${LEAKREPORT_OLD}
fi
EOF
    rlRun "chmod +x /usr/bin/kmemleakreport.sh"

    rlRun "echo hookup kmemleak report with rstrnt-reboot"
    sed -i "/shutdown -r/ikmemleakreport.sh" /usr/bin/rstrnt-reboot
}


rlJournalStart
    rlPhaseStartSetup
        ! test -f /mnt/DK_INSTALL && touch /mnt/DK_INSTALL && echo 0 > /mnt/DK_INSTALL
        if [ "${KERNTARGET}" == "rpm" ]; then
            install_kernelurl
        elif [ "${KERNTARGET}" == "upstream" ]; then
            install_upstream
        elif [ "${KERNTARGET}" == "debugkernel" ]; then
            install_debugkernel
        else
            install_brew_or_other
        fi
        hack_reboot
    rlPhaseEnd

    rlPhaseStartTest Test
        if [ -f ${LEAKFILE} ]; then
            report_leak
        elif [ -f "/mnt/DK_INSTALL" ]; then
            rlLogError "Didn't find $LEAKFILE for new kernel"
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
