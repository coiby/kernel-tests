#! /bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of cmdline
#   Description: Kpatch cmdline function test
#   Author: Chao Ye <cye@redhat.com>
#   Update: Chunyu Hu <chuhu@redhat.com>
#   Update: Yulia Kopkova <ykopkova@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
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

# trap 'rlFileRestore; exit' SIGHUP SIGINT SIGQUIT SIGTERM
trap 'killall make; exit 1' SIGHUP SIGINT SIGQUIT SIGTERM

MOD=${MOD:-}
built_kpatch_patch="/home/kpatch-patch-modules"
NFS_SHARE=${NFS_SHARE:-}
KPATCH_LOCATION=${KPATCH_LOCATION:-"/data/kpatch"}
KPATCH_SHARE="${NFS_SHARE}:${KPATCH_LOCATION}"
KPATCH_MNT="/mnt/kpatch"
MOUNT_FLAG=0

PATCHURL=${PATCHURL:-$KPATCHURL}
[ ! -z "${PATCHURL}" ] && PATCHRPM=$(eval basename "${PATCHURL}")

KPATCH_PATCH=${KPATCH_PATCH:-}
[ -z "${KPATCH_PATCH}" ] && { KPATCH_PATCH=$(rpm -qa | grep ^kpatch-patch);  KPATCH_PATCH=$(echo ${PATCHRPM%.rpm} | sed "s/.$(uname -m)//"); }

PACKAGE="kernel kpatch ${KPATCH_PATCH}"
echo ${PACKAGE}

GREP_STRING=${GREP_STRING:-kpatch}
TARGET_FILE=${TARGET_FILE:-/proc/cmdline}
MOD_PREFIX=${MOD_PREFIX:-test}

# -----------------------------------------------------------------------
# For kpatch-build built modules(not rpm)
get_modules_info() {
    loaded_modules=$(kpatch list | awk '/Loaded/, /Installed/ {print $1}' |egrep -v "^$|^Loaded|^Installed")
    installed_modules=$(kpatch list | awk '/Installed/, /*/ {print $1}' |egrep -v "^$|^Loaded|^Installed")
}

cleanup_modules() {
    ((SKIP_SETUP)) || return
    get_modules_info
    for k in ${loaded_modules}; do
        rlRun "kpatch force unload $k"
    done

    for k in ${installed_modules}; do
       echo ${USE_PATCHES//-/_} | grep $k && rlRun "kpatch uninstall $k"
    done
}

# This is for Y stream testing.
prepare_patches() {
    if [ -d ${built_kpatch_patch} ] && ls ${built_kpatch_patch}/*ko > /dev/null ; then
        echo "Test module is existed"
    elif ! mount | grep mnt/kpatch; then
        mount -t nfs "${KPATCH_SHARE}" "${KPATCH_MNT}" && { MOUNT_FLAG=1; echo "succeeded"; } || echo "failed"
        built_kpatch_patch="${KPATCH_MNT}/$(uname -r)"
    else
        echo "Already mounted $(mount | grep kpatch)"
    fi

    USE_PATCHES=${USE_PATCHES:-${MOD_PREFIX}-data-new $MOD_PREFIX-COMBINED}
    # kpatch-patch has been installed in previous execution
    # of this function.
    test -f KPATCH_INSTALL && { rlRun "kpatch list"; return; }

    ! test -e /usr/lib/kpatch/$(uname -r)/ &&  \
    rlRun "mkdir -p /usr/lib/kpatch/$(uname -r)/"
    rlRun "find ${built_kpatch_patch} -name kpatch.ko -exec \cp {} /usr/lib/kpatch/$(uname -r)/ \;" \
        || rlDie "Can't install kpatch.ko"

    local ko
    if [ "${USE_PATCHES}" = ALL ]; then
        echo "Use all patches under ${built_kpatch_patch}"
        find ${built_kpatch_patch} -name "${MOD_PREFIX}-*.ko" -exec kpatch install {} \;
        for ko in ${built_kpatch_patch}/${MOD_PREFIX}-*.ko; do
            rlRun "kpatch load ${ko//-/_}"
        done
    else
        rlLog "Use modules in ${built_kpatch_patch}: ${USE_PATCHES}"
        for ko in ${USE_PATCHES}; do
            if ! test -f ${built_kpatch_patch}/${ko}.ko; then
                rlLogWarning "${ko} does not exist!! Skip it.."
                continue
            fi
            EXIST_PATCHES+="${ko} "
            rlRun "kpatch install ${built_kpatch_patch}/${ko}.ko"
            rlRun "kpatch load ${ko//-/_}"
        done
        rlLog "Existed kpatch-patches ${EXIST_PATCHES}"
        [ -z "${EXIST_PATCHES}" ] && rlDie "there is no kpatch module ${USE_PATCHES}"
    fi
    # Dont' reinstall after a reboot.
    touch KPATCH_INSTALL

    rlRun "kpatch list"
}

#-------------------------------------------------------------------------------------------
run_kpatch() {
    rlRun "kpatch list"
    # When /sys/kernel/livepatch, kernel is using in-kernel livepatch support, dont need
    # to load kpatch module(kpatch.ko), which is the driver for kpatch.
    # When run here, either the the livepatch module (livepatch_) has been loaded.
    # or kpatch module has been loaded.
    rlRun "lsmod | grep ${MOD:-$MOD_PREFIX}"
    rlAssertEquals "lsmod should show ${MOD} loaded" 1 $(lsmod | grep -c ^${MOD})
    ((use_livepatch)) || rlAssertEquals "lsmod should show kpatch loaded" 1 $(lsmod | grep -c 'kpatch ')
    rlRun "kpatch info ${MOD}"
    rlAssertEquals "${MOD} should be installed and loaded" 2 $(kpatch list | grep -c ${MOD})
    rlRun "kpatch uninstall ${MOD}"
    rlRun "kpatch list"
    rlAssertEquals "${MOD} should be loaded and uninstalled" 1 $(kpatch list | grep -c ${MOD})
    rlRun "kpatch force unload ${MOD}"
    rlRun "kpatch list"
    rlAssertEquals "${MOD} should be unloaded and uninstalled" 0 $(kpatch list | grep -c ${MOD})
    rlRun "kpatch install ${MODPATH}"
    rlRun "kpatch list"
    rlAssertEquals "${MOD} should be unloaded and installed" 1 $(kpatch list | grep -c ${MOD})
    rlRun "kpatch load ${MOD}"
    rlRun "kpatch list"
    rlAssertEquals "${MOD} should be loaded and installed" 2 $(kpatch list | grep -c ${MOD})
    rlRun "kpatch force unload ${MOD}"
    rlRun "kpatch list"
    rlAssertEquals "${MOD} should be unloaded and installed" 1 $(kpatch list | grep -c ${MOD})

    rlRun -l "kpatch version" 0-254
    rlRun -l "kpatch" 0-254
}

run_checkproc() {
    if [ -z "${TARGET_FILE}" ] || [ -z "${GREP_STRING}" ];then
        rlLogWarning "Not clear what to check.There should be other test cases after this case."
        return 1;
    fi
    rlLog "Dummy patch applied, check ${TARGET_FILE} contain ${GREP_STRING}"
    rlAssertGrep "${GREP_STRING}" ${TARGET_FILE}
}

function kpatch_patch_testing() {
    if ! rpm -q ${PACKAGE}; then
        yum install -y ${PACKAGE}
        if ! rpm -q ${PACKAGE}; then
            rlDie "Failed to install ${PACKAGE}"
        fi
    fi

    if [ -n "${KPATCH_PATCH}" ]; then
        MODPATH=$(rpm -ql ${KPATCH_PATCH} | grep -E "kpatch-.*\.ko")
    fi

    if [ -z "${MODPATH}" ]; then
        MODPATH=$(ls /usr/lib/kpatch/$(uname -r)/kpatch-* | head -n 1)
    fi

    MOD="$(modinfo --field=name ${MODPATH})"
    [ -z "${MOD}" ] && MOD=$(basename ${MODPATH} | sed -e "s/-/_/g" | sed -e "s/.ko//")

    echo ${MOD}
    echo ${MODPATH}

    [ ! -e "/sys/module/${MOD}" ] && \
        ( rlRun "kpatch load ${MODPATH}" || rlDie "Cannot load ${MODPATH}" )
    rlAssertEquals "Assert ${MOD} is enabled" "$(cat /sys/kernel/livepatch/${MOD}/enabled)" "1" \
        ||  rlDie "Livepatch module ${MOD} is not enabled."

    changed_functions_test

    rlShowPackageVersion ${PACKAGE}

}

function changed_functions_test() {
    local changed_functions=""

    yumdownloader -q -y --source ${KPATCH_PATCH}
    rpm -i ${KPATCH_PATCH}
    pushd  /root/rpmbuild/SOURCES/
    changed_functions=$(grep -i 'changed function' *.patch | awk '{print $NF}')
    for c in ${changed_functions}; do
        rlLogInfo "$c function to be patched"
    done
    popd

    for f in ${changed_functions}; do
        if grep $f /sys/kernel/debug/tracing/enabled_functions; then
            rlReport "$f function is enabled" PASS
        else
            rlReport "$f function is enabled" WARN
        fi
    done
}

function label_check() {
    local var_kpatch_dir="/var/lib/kpatch/"
    if [ -d ${var_kpatch_dir} ]; then
        rlRun "ls -dZ ${var_kpatch_dir} | grep :var_lib_t" 1-254 "Selinux label Should not be var_lib_t"
        rlRun "ls -dZ ${var_kpatch_dir} | grep :kpatch_var_lib_t" 0 "Selinux label is kpatch_var_lib_t"
    else
        rlLogWarning "No ${var_kpatch_dir} Found"
    fi
}

function install_kpp()
{
    # Example of a kpatch-patch pkg "kpatch-patch-4_18_0-107-0-1.test.el8"
    local kpp_pkg kpp_name kpp_version kpp_release kpp_arch
    kpp_pkg=$1

    kpp_name=$(echo $KPATCH_PATCH | cut -d- -f1,2,3,4)
    kpp_version=$(echo $KPATCH_PATCH | cut -d- -f5)
    kpp_release=$(echo $KPATCH_PATCH | cut -d- -f6)
    kpp_arch=$(uname -m)

    yum -y install ${kpp_pkg} || \
        yum install -y "${BUILDS_URL}/${kpp_name}/${kpp_version}/${kpp_release}/${kpp_arch}/${kpp_pkg}.${kpp_arch}.rpm"
}

rlJournalStart
    test -d /sys/kernel/livepatch && use_livepatch=1
    if [ -z "${SKIP_SETUP}" ]; then
        rlPhaseStartSetup
            kpatch_patch_testing
        rlPhaseEnd
    else
        # This branch is for ystream testing.
        TARGET_FILE="/proc/meminfo"
        rlPhaseStartSetup "kpatch-patch modules"
            prepare_patches
            MOD=${MOD:-${MOD_PREFIX}_data_new}
            MODPATH=${MODPATH:-${built_kpatch_patch}/${MOD//_/-}.ko}
            MODNAME=${MODNAME:-$(basename $(echo ${MODPATH}))}
        rlPhaseEnd
    fi

    if ! [ -f REBOOT ]; then
        rlPhaseStartTest "Kpatch Cmdline function test"
            run_checkproc
            run_kpatch
            touch REBOOT
        rlPhaseEnd

        rhts-reboot
    else
        rlPhaseStartTest "Kpatch Cmdline reboot test"
            run_checkproc
            run_kpatch
        rlPhaseEnd
    fi

    rlPhaseStartTest "Kpatch selinux label test"
        label_check
        if [ -z "${SKIP_SETUP}" ] && [ ! -z "${KPATCH_PATCH}" ] ; then
            yum -y remove ${KPATCH_PATCH} && label_check
            install_kpp ${KPATCH_PATCH} && label_check
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -rf initramfs-$(uname -r) ${PATCHRPM}"
        sleep 2
        rm OVER -f
        rm ERROR -f
        cleanup_modules
        [ ${MOUNT_FLAG} == 1 ] && umount ${KPATCH_MNT}
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
