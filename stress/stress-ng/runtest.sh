#!/bin/bash
# shellcheck disable=SC2166
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/stress/stress-ng
#   Description: Run stress-ng test
#   Author: Jeff Bastian <jbastian@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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

# include beaker environment
. ../../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

TEST="stress/stress-ng"
BUILDDIR="/opt/stress-ng"

# task parameters
# stress-ng git location, mirroring from https://github.com/ColinIanKing/stress-ng.git
GIT_URL=${GIT_URL:-"https://gitlab.com/redhat/centos-stream/tests/stress-ng.git"}
# current release
GIT_BRANCH=${GIT_BRANCH:-"tags/V0.13.00"}
# test 'random' or 'sequential' class only by parameter passing
CLASSES=${CLASSES:-"interrupt cpu cpu-cache memory os"}
EXCLUDE_STRESSOR=${EXCLUDE_STRESSOR:-"close,cyclic,vfork"}
TIMEOUT=${TIMEOUT:-1h}

function detect_testenv()
{
    # Mustangs have a hardware flaw which causes kernel warnings under stress:
    #    list_add corruption. prev->next should be next
    if type -p dmidecode >/dev/null ; then
        if dmidecode -t1 | grep -q 'Product Name:.*Mustang.*' ; then
            rstrnt-report-result $TEST SKIP 0
            exit
        fi
    fi
}

function build_stress-ng()
{
    if [[ -f  "${BUILDDIR}/stress-ng" ]]; then
        rlLog "${BUILDDIR}/stress-ng is already built"
        return
    fi

    rlLog "Downloading stress-ng from source"
    rlRun "git clone $GIT_URL $BUILDDIR" 0
    if [ $? != 0 ]; then
        cki_abort_task "Failed to git clone $GIT_URL."
    fi

    # build
    rlLog "Building stress-ng from source"
    rlRun "pushd $BUILDDIR" 0
    rlRun "git checkout $GIT_BRANCH" 0
    rlRun "make" 0 "Building stress-ng"
    if [ $? != 0 ]; then
        rm -rf "$BUILDDIR"
        cki_abort_task "Failed to build stress-ng."
    fi
    rlRun "popd" 0 "Done building stress-ng"
}

function disable_systemd_coredump()
{
    # disable systemd-coredump collection
    if [ -f /lib/systemd/systemd ] ; then
        rlLog "Disabling systemd-coredump collection"
        if [ ! -d /etc/systemd/coredump.conf.d ] ; then
            mkdir /etc/systemd/coredump.conf.d
        fi
        cat >/etc/systemd/coredump.conf.d/stress-ng.conf <<EOF
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
        ln -s /dev/null /etc/sysctl.d/50-coredump.conf
        systemctl daemon-reload
        sysctl 'kernel.core_pattern=|/bin/false'
        sysctl kernel.core_uses_pid=0
    fi
}

function restore_systemd_coredump()
{
    # restore default systemd-coredump config
    if [ -f /lib/systemd/systemd ] ; then
        rm -f /etc/systemd/coredump.conf.d/stress-ng.conf
        rm -f /etc/sysctl.d/50-coredump.conf
        systemctl daemon-reload
        sysctl --system
    fi
}

function filter_excludelist()
{
    # exclude tests on certain arch, kernel, or distro
    if [ "$(uname -m)" = "ppc64le" ]; then
        # TODO: open BZ: vforkmany triggers kernel "BUG: soft lockup" on ppc64le
        sed -ie '/vforkmany/d' os.stressors
    fi

    if [[ "$(uname -r)" =~ 3.10.0.*rt.*el7 ]]; then
        # https://bugzilla.redhat.com/show_bug.cgi?id=1789039
        sed -ie '/af-alg/d' cpu.stressors
    fi

    if grep -q 'Fedora' /etc/redhat-release ; then
        # kernel BUG at mm/usercopy.c:99! for upstream kernels
        # https://bugzilla.kernel.org/show_bug.cgi?id=209919
        sed -ie '/procfs/d' os.stressors
    fi
}

function selinux_dccp()
{
    # stress-ng-dccp is blocked by SELinux (see RHBZ 1459941) on RHEL-7.x with
    # selinux-policy-3.13.1-175.el7 and earlier, so generate an SELinux module
    # to allow DCCP sockets
    if grep -q 'Red Hat Enterprise Linux.*release 7.*' /etc/redhat-release ; then
        rpmdev-vercmp "$(rpm -q --qf '%{epochnum}:%{version}-%{release}\n' selinux-policy)" "0:3.13.1-175.el7" >/dev/null
        if [ $? -eq 12 ]; then
            rlRun "yum -y install selinux-policy-devel" 0 "Installing SELinux development tools"
            rlRun "make -f /usr/share/selinux/devel/Makefile stress-ng-dccp.pp" 0 "Building stress-ng-dccp SELinux module"
            rlRun "semodule -i stress-ng-dccp.pp" 0 "Installing stress-ng-dccp SELinux module"
        fi
    fi
}

function customize_param()
{
    # known issue list:
    # Bug 1869760 - Host becomes unresponsive during stress-ng --cyclic test rcu:
    # Bug 1866855 - Host Unexpectedly Reboots: BUG: Bad rss-counter state mm:000000009db8edc6
    sed -i "s/#EXCLUDE_STRESSOR#/\"${EXCLUDE_STRESSOR}\"/g" *.stressors

    if [ ! -z "$TIMEOUT" ]; then
        sed -i "s/#TIMEOUT#/\"${TIMEOUT}\"/g" *.stressors
    fi

    # limit thread count on memory stressors to half the core count
    # https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/1425
    # mcontend gets special treatment for large systems
    # https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/1185
    if [[ $(nproc) -gt 16 ]]; then
        sed -i "/mcontend/s/XXX/16/" memory.stressors
    fi
    sed -i "s/XXX/$(($(nproc) / 2))/" memory.stressors
}

# ----- Test Start ------
rlJournalStart
rlPhaseStartSetup
    # if stress-ng triggers a panic and reboot, then abort the test
    if [ $RSTRNT_REBOOTCOUNT -ge 1 ] ; then
        cki_abort_task "Aborting due to system crash and reboot"
    fi

    detect_testenv
    build_stress-ng
    disable_systemd_coredump
    filter_excludelist
    selinux_dccp
    customize_param

    # disable swap for os class tests
    if [[ "$CLASSES" == "os" ]]; then
        rlRun "swapoff -a" 0 "disable swap for os class tests"
        res=$?
        if  [[ "$res" -eq 32 ]]; then
            rlLog "all swapoff failed on --all"
        elif [[ "$res" -eq 64 ]]; then
            rlLog "some swapoff failed on --all"
        fi

        # disable zram if needed
    if systemctl list-unit-files | grep -q systemd-zram-setup ; then
            rlRun "systemctl disable --now systemd-zram-setup@zram0" 0 "disable zram for os class tests"
            if [ -e /etc/systemd/zram-generator.conf ]; then
                rstrnt-backup /etc/systemd/zram-generator.conf
            fi
            cat /dev/null > /etc/systemd/zram-generator.conf
         fi

    fi

    getsebool selinuxuser_execmod >/dev/null 2>&1 && setsebool selinuxuser_execmod on
rlPhaseEnd

rlPhaseStartTest
    # Clean previous logs, if existed
    rm -f *.log > /dev/null 2>&1
    for CLASS in ${CLASSES} ; do
        while read STRESSOR ; do
            [[ ${STRESSOR} =~ ^# ]] && continue
            LOG=$(grep -o '[[:alnum:]]*\.log' <<<${STRESSOR})
            rlRun "${BUILDDIR}/stress-ng ${STRESSOR}" 0,2,3
            [ $? -eq 0 -o $? -eq 2 -o $? -eq 3 ] && RESULT="PASS" || RESULT="FAIL"
            rlReport "${CLASS}: ${STRESSOR}" ${RESULT} 0 ${LOG}
        done < ${CLASS}.stressors
    done
rlPhaseEnd

rlPhaseStartCleanup
    restore_systemd_coredump

    # remove selinux module
    if semodule -l | grep -q stress-ng-dccp ; then
        rlRun "semodule -r stress-ng-dccp" 0 "Removing stress-ng-dccp SELinux module"
    fi

    # re-enable swap after finishing os class tests
    if [[ "$CLASSES" == "os" ]]; then
        rlRun "swapon -a" 0 "re-enable swap back"

        if systemctl list-unit-files | grep -q systemd-zram-setup ; then
            rm -f /etc/systemd/zram-generator.conf
            rstrnt-restore
            rlRun "systemctl enable --now systemd-zram-setup@zram0" 0 "re-enable zram"

        fi
    fi

    getsebool selinuxuser_execmod >/dev/null 2>&1 && setsebool selinuxuser_execmod off
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
