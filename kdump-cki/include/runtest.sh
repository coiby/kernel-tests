#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


# Source  environment
. ../../cki_lib/libcki.sh || exit 1

K_TESTAREA="/mnt/testarea"
K_NFS="${K_TESTAREA}/KDUMP-NFS"
K_PATH="${K_TESTAREA}/KDUMP-PATH"
K_REBOOT="${K_TMP_DIR}/KDUMP-REBOOT"
C_REBOOT="./C_REBOOT"

KDUMP_CONFIG="/etc/kdump.conf"
KDUMP_SYS_CONFIG="/etc/sysconfig/kdump"
KDUMP_LOG="/var/log/kdump.log"
K_DEFAULT_PATH="/var/crash"

K_TMP_DIR="${K_TESTAREA}/tmp"

K_DEBUG=${K_DEBUG:-false}
K_NFSSERVER=${K_NFSSERVER:-""}
K_VMCOREPATH=${K_VMCOREPATH:-"/var/crash"}

UPGRADE_FC_KDUMP=${UPGRADE_FC_KDUMP:-"true"}
UPGRADE_FC_CRASH=${UPGRADE_FC_CRASH:-"true"}

mkdir -p ${K_TMP_DIR}

# Kernel Variables

if [[ $(rpm --queryformat '%{name}\n' -qf /boot/config-$(uname -r)) =~ "not owned by any package" ]]; then
    # kernel config/vmlinuz are installed from tarball, not dnf install
    K_NAME=kernel
    K_ARCH=$(uname -m)
    K_VER=$(uname -r | cut -d'-' -f1)
    K_REL=$(uname -r | cut -d'-' -f2-)
    K_KVARI=$(uname -r | grep -Eo '(debug|rt|rt(-)*debug|64k|64k-debug)$')
    K_SPEC_NAME=kernel
else
    # Example outputs: kernel-core, kernel-rt-core, kernel-rt-debug-core
    K_NAME=$(rpm --queryformat '%{name}\n' -qf /boot/config-$(uname -r))
    K_ARCH=$(uname -m)

    # Kernel version
    # Example outputs: 2.6.32, 4.18.0
    K_VER=$(rpm --queryformat '%{version}\n' -qf /boot/config-$(uname -r))

    # Kernel release
    # Example outputs: 1160.81.1.el7, 226.el9, 5.14.0-226.rt14.227.el9
    K_REL=$(rpm --queryformat '%{release}\n' -qf /boot/config-$(uname -r))

    # Example outputs: debug, xen, vanilla
    # Note, rt kernel (and rt debug kernel) will be treated as variants after
    # rt kernel source is merged to kernel tree.
    K_KVARI=$(uname -r | grep -Eo '(debug|PAE|xen|trace|vanilla|rt|rt(-)*debug|64k|64k-debug)$')

    # Example output: kernel-2.6.32-220.el6.src.rpm
    K_SRC=$(rpm --queryformat '%{sourcerpm}\n' -qf /boot/config-$(uname -r))

    # Example outputs: kernel-rt, kernel
    # This is a little cryptic, in practice it takes the full src rpm file
    # name and strips everything after (including) the version, leaving just
    # the src rpm package name.
    # Needed
    # - when the kernel rpm comes from of e.g. kernel-pegas src rpm.
    # - kernel-rt rpm comes from kernel src rpm (merged source tree)
    K_SPEC_NAME=${K_SRC%%"-${K_VER}"*}
fi

rlIsRHEL 5 && IS_RHEL5=true || IS_RHEL5=false
rlIsRHEL 6 && IS_RHEL6=true || IS_RHEL6=false
rlIsRHEL 7 && IS_RHEL7=true || IS_RHEL7=false
rlIsRHEL 8 && IS_RHEL8=true || IS_RHEL8=false
rlIsRHEL 9 && IS_RHEL9=true || IS_RHEL9=false
rlIsFedora && IS_FC=true || IS_FC=false
rlIsCentOS 8 && IS_CentOS8=true || IS_CentOS8=false
rlIsCentOS 9 && IS_CentOS9=true || IS_CentOS9=false
[[ "$FAMILY" =~ CentOSStream ]] && IS_COS=true || IS_COS=false
[[ "$FAMILY" =~ RedHatEnterpriseLinux ]] && IS_RHEL=true || IS_RHEL=false

if $IS_FC || $IS_COS; then
    RELEASE=$(grep -o 'release [^ ]*' /etc/redhat-release  | awk '{print $NF}')
else
    RELEASE=$(grep -o 'release [^.]*' /etc/redhat-release | awk '{print $NF}')
fi

uname -v | grep -q PREEMPT_RT && IS_RT=true || IS_RT=false
uname -r | grep -qE "[-+]debug" && IS_DB=true || IS_DB=false
uname -r | grep -qE "[-+]64k" && IS_64K=true || IS_64K=false

if $IS_RHEL5; then
    INITRD_PREFIX=initrd
else
    INITRD_PREFIX=initramfs
fi
INITRD_IMG_PATH="/boot/$INITRD_PREFIX-`uname -r`.img"

shopt -s extglob
if stat /run/ostree-booted > /dev/null 2>&1; then
    K_BOOT="/usr/lib/ostree-boot"
    INITRD_IMG_PATH=$(find $K_BOOT -name "${INITRD_PREFIX}-$(uname -r).img-*")
else
    [ "${K_ARCH}" = "ia64" ] && K_BOOT="/boot/efi/efi/redhat" || K_BOOT="/boot"
    INITRD_IMG_PATH="$K_BOOT/$INITRD_PREFIX-$(uname -r).img"
fi

INITRD_KDUMP_IMG_PATH=$(sed -e "s/\.img$/kdump.img/; s/$INITRD_PREFIX/$INITRD_KDUMP_PREFIX/" <<< "$INITRD_IMG_PATH")
VMLINUZ_PATH=$(ls ${K_BOOT}/vmlinuz-$(uname -r)!(*debug*|*64k*|*rt*))
[ -z "${VMLINUZ_PATH}" ] && VMLINUZ_PATH=$(ls ${K_BOOT}/vmlinux-$(uname -r)!(*debug*|*64k*|*rt*))




# Backup kdump config files
BackupKdumpConfig()
{
    [ -f "${KDUMP_CONFIG}" -a ! -f "${KDUMP_CONFIG}.bk" ] && cp "${KDUMP_CONFIG}" "${KDUMP_CONFIG}.bk"
    [ -f "${KDUMP_SYS_CONFIG}" -a ! -f "${KDUMP_SYS_CONFIG}.bk" ] && cp "${KDUMP_SYS_CONFIG}" "${KDUMP_SYS_CONFIG}.bk"
}

# back up kdump config files
BackupKdumpConfig

DisableAVCCheck()
{
  echo "Disable AVC check"
  export AVC_ERROR=+no_avc_check
}

# Disable AVC Check for all kdump tests
DisableAVCCheck

# Erase possible preceding/trailing white spaces.
Chomp()
{
    echo "$1" | sed '/^[[:space:]]*$/d;
        s/^[[:space:]]*\|[[:space:]]*$//g'
}

TurnDebugOn()
{
    if $IS_RHEL7 || $IS_RHEL8 || $IS_RHEL9 ; then
        sed -i 's;\(/bin/sh\)$;\1 -x;' /usr/bin/kdumpctl
        sed -i 's;2>/dev/null;;g' /usr/bin/kdumpctl
    else
        sed -i 's;\(/bin/sh\);\1 -x;' /etc/init.d/kdump
    fi
}

CommandExists()
{
    local cmd=$1
    if [ -z "$cmd" ]; then
        return 1
    elif which $cmd > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

CheckEnv()
{
    # Check test environment.
    if [ -z "${RSTRNT_JOBID}" ]; then
        Log "Variable RSTRNT_JOBID does not set! Assume developer mode."
        SERVERFILE="Server-$(date +%H_%j)"
        DEVMODE=true
    else
        SERVERFILE="Server-${RSTRNT_JOBID}"
    fi
}

PrepareReboot()
{
    # IA-64 needs nextboot set.
    if [ -e "/usr/sbin/efibootmgr" ]; then
        EFI=$(efibootmgr -v | grep BootCurrent | awk '{ print $2}')
        if [ -n "$EFI" ]; then
            Log "- Updating efibootmgr next boot option to $EFI according to BootCurrent"
            efibootmgr -n $(efibootmgr -v | grep BootCurrent | awk '{ print $2}')
        elif [[ -z "$EFI" && -f /root/EFI_BOOT_ENTRY.TXT ]] ; then
            os_boot_entry=$(</root/EFI_BOOT_ENTRY.TXT)
            Log "- Updating efibootmgr next boot option to $os_boot_entry according to EFI_BOOT_ENTRY.TXT"
            efibootmgr -n $os_boot_entry
        else
            Log "- Could not determine value for BootNext!"
        fi
    fi
}

RunTest()
{
    local func=$1
    local stage=$2

    warn=0
    error=0
    skip=0
    CheckEnv

    # Check test type.
    if [ -z "${SERVERS}" ] && [ -z "${CLIENTS}" ]; then
        # single host test
        ${func}

    elif echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
        TEST="${TEST}/client"
        ${func}
        Log "Client finishes."

    elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
        TEST="${TEST}/server"
        # Do nothing.
        Log "Server finishes."

    else
        Error "Neither server nor client"
    fi

    Report $stage
}

CheckVmlinux()
{
    vmlinux="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
    if [ -f "${vmlinux}" ]; then
        Log "Kernel debug vmlinux is ready at ${vmlinux}"
    else
        Log "Kernel debug vmlinux is not found at ${vmlinux}"
        return 1
    fi
}


#  Common Log Functions/Variables.

declare -i error warn skip

GetLogPrefix() {
    local timestamp=$(date +%H:%M:%S)
    case "${1^^}" in
        LOG)
            echo "[  ${timestamp}  ] :: [  LOG  ] :: "
        ;;
        RUN)
            echo "[  ${timestamp}  ] :: [  RUN  ] :: "
        ;;
        SKIP)
            echo "[  ${timestamp}]   :: [  SKIP ] :: "
        ;;
        WARN)
            echo "[  ${timestamp}  ] :: [  WARN ] :: "
        ;;
        ERROR)
            echo "[  ${timestamp}  ] :: [ ERROR ] :: "
        ;;
        FATAL)
            echo "[  ${timestamp}  ] :: [ ERROR ] :: "
        ;;
        *)
            echo "[  ${timestamp}  ] :: [  LOG  ] :: "
        ;;
    esac
}

Log() {
    echo -e "$(GetLogPrefix LOG)$1" | tee -a "${OUTPUTFILE}"
}

LogRun() {
    echo -e "$(GetLogPrefix RUN)# $*" | tee -a "${OUTPUTFILE}"

    eval "$*" | tee -a "${OUTPUTFILE}"
    local ret=${PIPESTATUS[0]}
    return ${ret}
}

Skip() {
    echo -e "$(GetLogPrefix SKIP)$1" | tee -a "${OUTPUTFILE}"
    skip=$((skip + 1))

    Report
}

Warn() {
    echo -e "$(GetLogPrefix WARN)$1" | tee -a "${OUTPUTFILE}"
    warn=$((warn + 1))
}

# error occurs - but won't abort recipe set
Error() {
    echo -e "$(GetLogPrefix ERROR)$1" | tee -a "${OUTPUTFILE}"
    error=$((error + 1))
}

# major error occurs - stop current test task and proceed to next test task.
# do not abort recipe set
MajorError() {
    echo -e "$(GetLogPrefix ERROR)$1" | tee -a "${OUTPUTFILE}"
    error=$((error + 1))

    # If it's the client in a multi-hosts test, sent out sync message
    # before finish tests.
    if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
        rhts_sync_set -s "DONE"
    fi
    Report
}

# fatal error occurs - must abort recipe set
FatalError() {
    echo -e "$(GetLogPrefix FATAL)$1" | tee -a "${OUTPUTFILE}"
    echo -e "$(GetLogPrefix FATAL)Aborting the recipe set" | tee -a "${OUTPUTFILE}"

    error=$((error + 1))
    rstrnt-report-result "${TEST}" "FAIL" "${error}"
    rstrnt-abort -t recipeset
}

Report() {
    local stage="$1"
    local code

    if (( error != 0 )); then
        result="FAIL"
        code=${error}
    elif (( warn != 0 )); then
        result="WARN"
        code=${warn}
    elif (( skip != 0 )); then
        result="SKIP"
        code=0
    else
        result="PASS"
        code=0
    fi

    echo ":::::::::::::::::::::::::::::::::::::::::::::"
    [ -n "${stage}" ] && echo -e ":: PHASE: $stage"
    echo -e ":: RESULT: ${result} (skip: ${skip:-0} warn: {warn:-0} error: ${error:-0})"
    echo ":::::::::::::::::::::::::::::::::::::::::::::"


    #reset codes to avoid propogating them
    error=0
    warn=0
    skip=0

    if [ -n "${stage}" ]; then
        rstrnt-report-result "${TEST}/${stage}" "${result}" "${code}"
    else
        rstrnt-report-result "${TEST}" "${result}" "${code}"
        exit 0
    fi
}

RstrntSubmit() {
    [ ! -f "$1" ] && return

    local size
    size=$(wc -c < "$1")
    # zip and upload the zipped file if the size of which is larger than 100M
    if [ "$size" -ge 100000000 ]; then
        Log "- Size of File $1 is larger than 100M. Uploading the zipped file."
        zip "${1}.zip" "${1}"
        rstrnt-report-log -l "${1}.zip"
    else
        rstrnt-report-log -l "${1}"
    fi
}

SafeReboot() {
    # It will config BootNext to be same as current boot for EFI boot machine.
    rstrnt-reboot
    # Make sure the script doesn't continue if rstrnt-reboot get's killed
    # https://github.com/beaker-project/restraint/issues/219
    exit 0
}


GetBiosInfo()
{
    # Get BIOS information.
    rpm -q --quiet dmidecode || InstallPackages dmidecode
    CommandExists dmidecode && {
        dmidecode >"${K_TMP_DIR}/bios.output"
        RstrntSubmit "${K_TMP_DIR}/bios.output"
    }
}

GetHWInfo()
{
    rpm -q --quiet lshw || InstallPackages lshw
    lshw > "${K_TMP_DIR}/lshw.output"
    RstrntSubmit "${K_TMP_DIR}/lshw.output"

    CommandExists lscfg && {
        lscfg > "${K_TMP_DIR}/lscfg.output"
        RstrntSubmit "${K_TMP_DIR}/lscfg.output"
    }
}

ReportSystemInfo()
{
    Log "Upload system hardware info"
    [[ "${K_ARCH}" =~ i.86|x86_64 ]] && GetBiosInfo
    GetHWInfo
}

ClearReport()
{
    rm -rf ${K_TMP_DIR}
}


#  Common Kdump/Crash Functions

# Install/Upgrade Kexec-tools and related packages
PrepareKdump()
{
    Log "Install kexec-tools and related packages"
    rpm -q --quiet kexec-tools || {
        # On Fedora, kexec-tools is not installed by default.
        # Install kexec-tools and enable kdump service.
        InstallPackages kexec-tools
        rpm -q kexec-tools || {
            Log "- Aborting test as kexec-tools couldn't be installed"
            rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
            rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
            exit 1
        }
        systemctl enable kdump.service || chkconfig kdump on

        # Back up configurations if kexec-tools is installed for the first time
        BackupKdumpConfig
    }

    # Try upgrading kexec-tools to the latest version if on FC.
    # If it fails, still use the kexec-tools from the default repo.
    if $IS_FC && $UPGRADE_FC_KDUMP; then
        UpgradePackages kexec-tools dracut systemd selinux-policy --enablerepo=updates-testing --enablerepo=fedora --releasever=rawhide
    fi
}

# Install/Upgrade Crash and related packages
PrepareCrash()
{
    Log "Install crash"
    rpm -q crash || InstallPackages crash
    # Try upgrading crash to the latest version if on FC.
    # If it fails, still use the crash from the default repo.
    if $IS_FC && $UPGRADE_FC_CRASH; then
        UpgradePackages crash --enablerepo=updates-testing --enablerepo=fedora --releasever=rawhide
    fi

    InstallDebuginfo
    CheckVmlinux || {
        Log "- Warn: Skip running crash utitlies against the vmcore."
        return 1
    }
}

# Config kernel options and make sure Kdump is operational
SetupKdump()
{

    if [ ! -f "${K_REBOOT}" ]; then
        Log "Prepare Kdump"
        PrepareKdump

        local default=/boot/vmlinuz-`uname -r`
        [ ! -s "$default" ] && default=/boot/vmlinux-`uname -r`

        # For uncompressed kernel, i.e. vmlinux
        [[ ${default} == *vmlinux* ]] && {
            Log "Modifying /etc/sysconfig/kdump properly for 'vmlinux'."
            sed -i 's/\(KDUMP_IMG\)=.*/\1="vmlinux"/' /etc/sysconfig/kdump
        }

        # For kernel-rt
        $IS_RT && [ -f /usr/bin/rt-setup-kdump ] && {
            Log "Modifying /etc/sysconfig/kdump properly for RT."
            set -x; /usr/bin/rt-setup-kdump -g; set +x
        }

        # Ensure Kdump Kernel memory reservation
        grep -q 'crashkernel' <<< "${KER1ARGS}" || {
            local kdumpMem=$(DefKdumpMem)
            [ -z "${KER1ARGS}" ] || kdumpMem=" ${kdumpMem}"

            if $IS_RHEL5 ; then
                KER1ARGS+="${kdumpMem}"
            elif [ "$(cat /sys/kernel/kexec_crash_size)" -eq 0 ] ; then
                # Check kdump status if it's fadump mode which caused kexec_crash_size is 0
                kdumpctl status > /dev/null 2>&1 || KER1ARGS+="${kdumpMem}"
            fi
        }

        [ "${KER1ARGS}" ] && {
            touch "${K_REBOOT}"

            # Kdump service will not be enabled if crashkernel=auto && system
            # memory is less the threshold required by kdump service.
            Log "Enable kdump service"
            systemctl enable kdump.service || chkconfig kdump on
            rpm -q --quiet grubby || InstallPackages grubby
            Log "Update boot loader"
            UpdateKernelOptions "${KER1ARGS}" || FatalError "Error changing boot loader."

            Report 'pre-reboot'
            Log "Rebooting..."; sync; SafeReboot
        }
    fi

    # Make sure kdump service fully up after a boot
    # If kdump service is not started yet, wait for max 5 mins.
    # It may take time to start kdump service.
    Log "Waiting for kdump service to be fully up"
    local kdump_status=off
    for i in {1..5}
    do
        kdumpctl status 2>&1 || service kdump status 2>&1
        [ $? -eq 0 ] && {
            kdump_status=on
            break
        }
        sleep 60
    done

    ReportSystemInfo
    Log "Packages versions:"
    uname -r; rpm -q kexec-tools systemd dracut

    Log "Kernel cmdline and crash memory reservation"
    cat /proc/cmdline
    echo "Total system memory: $(lshw -short | grep -i "System Memory" | awk '{print $3}')"
    kdumpctl showmem || cat /sys/kernel/kexec_crash_size
    grep -q "fadump=on" /proc/cmdline && {
        Log "Crash memory reserved for fadump:"
        if CommandExists journalctl ; then
            journalctl | grep -i "firmware-assisted" | grep -i "Reserved"
        else
            dmesg | grep -i "firmware-assisted" | grep -i "Reserved"
        fi
    }

    [ -f "${K_REBOOT}" ] && rm -f "${K_REBOOT}"
}

DefKdumpMem()
{
    local args=""

    if $IS_RHEL6; then
        if   [[ "${K_ARCH}" == i?86     ]]; then args="crashkernel=128M"
        elif [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=128M"
        elif [[ "${K_ARCH}"  = "ppc64"  ]]; then args="crashkernel=256M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=128M"
        fi

    elif $IS_RHEL7; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=160M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=160M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0M-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=512M"
        fi

    elif $IS_RHEL8 || $IS_CentOS8; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=0G-4G:160M,4G-64G:192M,64G-1T:256M,1T-:512M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=0G-4G:160M,4G-64G:192M,64G-1T:256M,1T-:512M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0M-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=512M"
        fi

    elif $IS_RHEL9 || $IS_CentOS9; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=0G-4G:192M,4G-64G:192M,64G-1T:256M,1T-:512M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=0G-4G:192M,4G-64G:192M,64G-1T:256M,1T-:512M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0M-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=512M"
        fi

    elif $IS_FC; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=0G-4G:256M,4G-64G:256M,64G-1T:256M,1T-:512M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=0G-4G:192M,4G-64G:192M,64G-1T:256M,1T-:512M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0M-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=512M"
        fi

    elif $IS_RHEL5; then
        if   [[ "${K_ARCH}" == i?86     ]]; then args="crashkernel=128M@16M"
        elif [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=128M@16M"
        elif [[ "${K_ARCH}"  = "ppc64"  ]]; then args="crashkernel=256M@32M xmon=off"
        elif [[ "${K_ARCH}"  = "ia64"   ]]; then args="crashkernel=512M@256M";
            # the larger IA-64 box, the more kdump memory needed
            grep -qE '^ACPI:.*(rx8640|SGI)' /var/log/dmesg &&
            args="crashkernel=768M@256M"
        fi
    fi

    echo "$args"
}

ResetKdumpConfig()
{
    Log "- Reset to default kdump config"
    echo > "${KDUMP_CONFIG}"
    echo "path /var/crash" >>"${KDUMP_CONFIG}"
    echo "core_collector makedumpfile -l --message-level 7 -d 31" >>"${KDUMP_CONFIG}"
}


TriggerSysrqPanic()
{
    touch "${C_REBOOT}"
    sync;sync;sync

    PrepareReboot

    Log "Alert: Triggering crash"
    echo 1 > /proc/sys/kernel/sysrq
    echo c > /proc/sysrq-trigger

    sleep 60
    Error "Failed to trigger crash after waiting for 60s"
}

AppendConfig()
{
    Log "Modifying ${KDUMP_CONFIG}"

    if [ $# -eq 0 ]; then
        Warn "Nothing to append."
        return 0
    fi

    while [ $# -gt 0 ]; do
        Log "- Removing existed old ${1%%[[:space:]]*} settings."
        sed -i "/^${1%%[[:space:]]*}/d" "${KDUMP_CONFIG}"
        Log "- Adding new '$1'."
        echo "$1" >>"${KDUMP_CONFIG}"
        shift
    done

    RstrntSubmit "${KDUMP_CONFIG}"
}


AppendSysconfig()
{
    Log "Modifying ${KDUMP_SYS_CONFIG}"

    local KEY=$1
    local ACTION=$2
    local VALUE1=$3
    local VALUE2=$4

    if [ -z "$KEY" ] || [ -z "$ACTION" ] || [ -z "$VALUE1" ]; then
        Error "- Missing KEY or ACTION or VALUE1."
        return 1
    elif [ "$ACTION" = "replace" ] && [ -z "$VALUE2" ]; then
        Error "- Missing new_value for replacing."
        return 1
    elif ! grep -q "^$KEY=\"" "${KDUMP_SYS_CONFIG}"; then
        Error "- Invalid KEY: $KEY."
        return 1
    fi

    local kdump_sys_config_tmp="${KDUMP_SYS_CONFIG}.tmp"
    \cp "${KDUMP_SYS_CONFIG}" "${kdump_sys_config_tmp}"

    # Note: When KEY is "KDUMP_COMMANDLINE", ACTION add/remove/replace is actually
    # manipulating the value of current kernel cmdline and assign
    # it to KDUMP_COMMANDLINE.
    # if there is no value set to KDUMP_COMMANDLINE, assign current kernel cmdline
    # to it for later string manipluation.
    if [ "$KEY" == "KDUMP_COMMANDLINE" ] && \
        grep -q "^$KEY=[\ \"]*$" "${kdump_sys_config_tmp}"; then

        sed -i "/^KDUMP_COMMANDLINE=\"/d" "${kdump_sys_config_tmp}"
        echo "KDUMP_COMMANDLINE=\"$(cat /proc/cmdline)\"" >> "${kdump_sys_config_tmp}"
    fi

    case $ACTION in
        add)
            # Check if the key already has a value on it, then append " $VALUE1" to the
            # original value.
            Log "- Add '$VALUE1' to '$KEY'"
            if grep -q "^$KEY=[\ \"]*$" "${kdump_sys_config_tmp}"; then
                sed -i /^"$KEY="/d "${kdump_sys_config_tmp}"
                echo "$KEY=\"$VALUE1\"" >> "${kdump_sys_config_tmp}"
            else
                sed -i "/^$KEY=/s/\"/\"$VALUE1 /" "${kdump_sys_config_tmp}"
            fi
            ;;
        remove)
            Log "- Remove '$VALUE1' from '$KEY'"
            sed -i  "/^$KEY=/s/$VALUE1//g" "${kdump_sys_config_tmp}"
            ;;
        replace)
            Log "- Replace '$VALUE1' with '$VALUE2' for '$KEY'"
            sed -i  "/^$KEY=/s/$VALUE1/$VALUE2/g" "${kdump_sys_config_tmp}"
            ;;
        override)
            Log "- Set '$VALUE1' to '$KEY'"
            sed -i "/^$KEY=\"/d" "${kdump_sys_config_tmp}"
            echo "$KEY=\"$VALUE1\"" >> "${kdump_sys_config_tmp}"
            ;;
        *)
            Error "- Invalid action '${ACTION}' for editing kdump sysconfig."
            false
            ;;
    esac

    [ $? -ne 0 ] && {
        Error "- Failed to edit kdump sysconfig"
        rm -f "${kdump_sys_config_tmp}"
        return 1
    }

    \mv "${kdump_sys_config_tmp}" "${KDUMP_SYS_CONFIG}"
    RstrntSubmit "${KDUMP_SYS_CONFIG}"
    sync;sync;sync # best try to make sure the configs written to disk before panic
    return 0
}

ReportKdumprd()
{
    Log "Uploading kdump initramfs image"
    if $IS_RHEL5 || $IS_RHEL6; then
        tmp=initrd
    else
        tmp=initramfs
    fi

    # Submit Kdump initramfs.
    if grep -q "fadump=on" < /proc/cmdline; then
        kdumprd=${K_BOOT}/$tmp-$(uname -r).img
    else
        kdumprd=${K_BOOT}/$tmp-$(uname -r)kdump.img
    fi

    if [ -f "${kdumprd}" ]; then
        RstrntSubmit "${kdumprd}"
    else
        Error 'Not found kdump initramfs img at ${kdumprd}'
    fi

    sync
}

# print out kdump status
# no error handling
CheckKdumpStatus()
{
    LogRun "kdumpctl status" || LogRun "service kdump status" || LogRun "systemctl status kdump"
}

RestartKdump()
{
    local tmp=""
    local kdumprd=""
    local rc=
    local UPLOADRD=${1:-"false"}

    Log "Restarting Kdump service."

    rm -f /boot/initrd-*kdump.img
    rm -f /boot/initramfs-*kdump.img    # For RHEL7
    touch "${KDUMP_CONFIG}"
    RstrntSubmit "${KDUMP_CONFIG}"
    RstrntSubmit "${KDUMP_SYS_CONFIG}"

    if $IS_RHEL5 || $IS_RHEL6; then
        tmp=initrd
        /sbin/service kdump restart 2>&1 | tee /tmp/kdump_restart.log
        /sbin/service kdump status  2>&1
    else
        tmp=initramfs
        /usr/bin/kdumpctl showmem 2>&1
        /usr/bin/kdumpctl restart 2>&1 | tee /tmp/kdump_restart.log
        /usr/bin/kdumpctl status  2>&1
    fi

    local retval=$?

    RstrntSubmit "${KDUMP_LOG}"

    [ "$retval" -ne 0 ] && FatalError 'Restarting kdump failed.'
    sync; sync; sleep 10

    # It may report "No kdump initial ramdisk found.[WARNING]" in rhel6
    local skip_pat="No kdump initial ramdisk found|Warning: There might not be enough space to save a vmcore|Warning no default label"
    if grep -v -E "$skip_pat" /tmp/kdump_restart.log |  grep -q -i -E "can't|error|warn";  then
        Warn 'Restarting kdump reported warn/error message'
    fi
    sync;

    if [ "${UPLOADRD}" == true ]; then
        ReportKdumprd
    fi
}


InstallPackages()
{
    local action=install
    if [ "${1,,}" = "upgrade" ]; then
        shift
        action=upgrade
    fi
    local pkgs="$*"

    [ $# -eq 0 ] && {
        Error "No package specified for ${action}ing"
        return 1
    }

    if stat /run/ostree-booted > /dev/null 2>&1; then
        LogRun "rpm-ostree install --apply-live --allow-inactive --idempotent -y $pkgs"
    else
        if CommandExists dnf ; then
            LogRun "dnf $action -y $pkgs"
        elif CommandExists yum ; then
            LogRun "yum $action -y $pkgs"
        else
            return 1
        fi
    fi
}

UpgradePackages()
{
    InstallPackages upgrade $*
}

InstallDebuginfo()
{
    local kern=$(rpm -qf /boot/vmlinuz-$(uname -r) --qf "%{name}-debuginfo-%{version}-%{release}.%{arch}" | sed -e "s/-core//g")
    if [[ "$kern" == *"is not owned by any package" ]]; then
        Log "Kernel is installed from a tar, not from yum/dnf. Expect kernel-debuginfo to be prepared in cki boot test."
        return
    fi

    Log "Install ${kern}"
    rpm -q ${kern} || {
        InstallPackages ${kern}
        rpm -q ${kern} || {
            Log "- Failed to install ${kern}"
            return 1
        }
    }

}

# Update kernel options
# Parameters
#   1: Options. If starting with "-" means it's going to removed.
#   2: Kernel: The kernel going to be updated. Default to curent running kernel
UpdateKernelOptions()
{
    Log "Updating kernel options"

    options="${1}"
    kernel="${2:-"${VMLINUZ_PATH}"}"

    if [ -z "${options}" ]; then
        Error "Empty options provided"
        return 1
    fi

    if stat /run/ostree-booted > /dev/null 2>&1; then
        action="--append-if-missing"
    else
        action="--args"
    fi
    if grep -q ^- <<< "${options}"; then
        if stat /run/ostree-booted > /dev/null 2>&1; then
            action="--delete-if-present"
        else
            action="--remove-args"
        fi
        options="$(sed "s/^-//" <<< ${options})"
    fi

    {
        if stat /run/ostree-booted > /dev/null 2>&1; then
            LogRun "rpm-ostree kargs ${action}=\"${options}\" --import-proc-cmdline"
        else
            LogRun "/sbin/grubby ${action}=\"${options}\" --update-kernel=\"${kernel}\"" &&
            if [ "${K_ARCH}" = "s390x" ]; then zipl; fi
        fi
    } || {
        Error "Failed to update option: ${options} on kernel ${kernel}"
        return 1
    }
    return 0
}

LsCore()
{
    LogRun "ls -l ${vmcore}" && FatalError "ls returns errors."
}

GetDumpFile()
{
    [ -z "$1" ] && return 1

    Log "Checking dumped file: ${1}"
    local file_name="$1"
    local core_dir="${K_DEFAULT_PATH}"

    dump_file_path=""

    [ -f "${K_PATH}" ] && core_dir="$(cat ${K_PATH})"
    [ -f "${K_NFS}" ] && core_dir="$(cat ${K_NFS})${core_dir}"

    # Print files under ${coredir}
    LogRun "find ${core_dir}"

    # Find the dump file (vmcore or dmesg files)
    dump_file_path=$(ls -t -1 "${core_dir}"/*/${file_name} 2>/dev/null | head -1)
    if [ -z "${dump_file_path}" ]; then
        Error "No ${file_name} saved in ${core_dir}. Please check kdump process in console.log"
        return 1
    elif [ ! -s "${dump_file_path}" ]; then
        Error "The ${file_name} is empty. Please check kdump process in console.log"
        return 1
    else
        LogRun "file -i ${dump_file_path}"
        Log "${file_name} path: ${dump_file_path}"
        return 0
    fi
}

GetCorePath()
{
    GetDumpFile "vmcore"
    local retval=$?
    vmcore="${dump_file_path}"
    return $retval
}

SimpleCrashAnalyseTest()
{
    # Only check the return code of this session.
    cat <<EOF > "${K_TESTAREA}/crash-simple.cmd"
bt -a
ps
log
exit
EOF

    Log "Simple crash tests against the vmcore"
    CrashCommand "" "${vmlinux}" "${vmcore}"
}

CrashCommand()
{
    local args=$1; shift
    local aux=$1; shift
    local core=$1; shift
    # allow passing cmd file other than default crash.cmd or crash-simple.cmd
    local cmd_file=$1; shift

    local result=0
    CrashCommand_CheckReturnCode "${args}" "${aux}" "${core}" "${cmd_file}" || result=1
}

# Run crash cmd defined in $cmd_file. Only return code is checked.
# Output:
#   ${cmd_file%.*}.log if on a live system
#   ${cmd_file%.*}.vmcore.log if on a vmcore
CrashCommand_CheckReturnCode()
{
    local args=$1; shift
    local aux=$1; shift
    local core=$1; shift
    local cmd_file=${1:-"crash-simple.cmd"}; shift
    local log_suffix
    [ -z "$core" ] && log_suffix=log || log_suffix="${core##*/}.log"

    Log "- Only check the return code of this session."
    Log "# crash ${args} -i ${K_TESTAREA}/${cmd_file} ${aux} ${core}"

    if [ -f "${K_TESTAREA}/${cmd_file}" ]; then
        crash ${args} -i "${K_TESTAREA}/${cmd_file}" ${aux} ${core} \
                > "${K_TESTAREA}/${cmd_file%.*}.$log_suffix" 2>&1 <<EOF
EOF
        code=$?

#        echo | tee -a "${OUTPUTFILE}"
        RstrntSubmit "${K_TESTAREA}/${cmd_file%.*}.$log_suffix"
        RstrntSubmit "${K_TESTAREA}/${cmd_file}"

        if [ ${code} -eq 0 ]; then
            return 0
        else
            Error "- Crash returns error code ${code}."
            return 1
        fi

    fi
}

RemoveVmcores()
{
    Log "Remove vmcores"
    local path
    # Do not remove anything if it's a NFS kdump target
    [ ! -f "${K_NFS}" ] && {
        if [ -f "${K_PATH}" ]; then
            path=$(cat "${K_PATH}")
        else
            path=${K_DEFAULT_PATH}
        fi

        # Check again if the vmcore path is a mounted remoted file system.
        # If yes, do not remove any files under the path
        df -T "${path}" | tail -n 1 | awk '{print $2}' | grep -q nfs
        if [ "$?" -ne 0 ] && [ -d "${path}" ]; then
            Log "- Remove all files in ${path}"
            rm -rf "${path}"/*
            return
        fi
    }
    Log "- Nothing removed"
}

RestoreKdumpConfig()
{
    Log "Restore Kdump configurations"
    # If nfs kdump is configured, unmount the kdump nfs target
    [ -f "${K_NFS}" ] && {
        path=$(cat "${K_NFS}")
        LogRun "umount \"${path}\""
    }

    rm -f "${K_NFS}" "${K_PATH}"

    Log "- Restore default /etc/kdump.conf"
    echo > "${KDUMP_CONFIG}"
    [ -f "${KDUMP_CONFIG}.bk" ] && \cp -f "${KDUMP_CONFIG}.bk" "${KDUMP_CONFIG}"

    Log "- Restore default /etc/sysconfig/kdump"
    [ -f "${KDUMP_SYS_CONFIG}.bk" ] && \cp -f "${KDUMP_SYS_CONFIG}.bk" "${KDUMP_SYS_CONFIG}"
}

# TestCleanup
# - Restore Kdump default configurations
# - Clean up vmcores
Cleanup(){
    echo ":::::::::::::::::::::::::::::::::::::::::::::"
    echo -e ":: TEST CLEANUP"
    RemoveVmcores
    RestoreKdumpConfig
    echo ":::::::::::::::::::::::::::::::::::::::::::::"
}

# Kexec load and reboot to kexec kernel
# GLOBALS:
#   EXTRA_KEXEC_OPTIONS - Extra options passed to kexec command
#   EXEC_VER - Version of kernel it kexecs to.
# Params:
#   1) test_boot_option: String will be appended to kexec kernel options
#   2) init_reboot_count: Allow setting the init reboot count in case the test
#   reboots system before calling KexecBoot(). Default is 0.
KexecBoot()
{
    local test_boot_option=${1:-"newkerneloption"}
    local init_reboot_count=${2:-0}

    if [ "$RSTRNT_REBOOTCOUNT" -eq "$init_reboot_count" ]; then
        Log "Kexec Phase 1: Run kexec to load and then reboot"

        # On aarch64, Kexec load is supported only if it's supporting PSCI
        if [ "$K_ARCH" = "aarch64" ]; then
            local supported=1
            if command -v journalctl &> /dev/null; then
                journalctl -k | grep -i psci | grep -i "is not implemented" && supported=0
            else
                grep -i  psci /var/log/messages | grep -i "is not implemented" && supported=0
            fi
            if [ "$supported" -eq 0 ]; then
                Skip "- Warn: This aarch64 system doesn't support PSCI. Terminate the test."
                return
            fi
        fi

        Log "- Current kernel and options are: "
        Log "$(uname -r)"
        Log "$(cat /proc/cmdline)"

        PrepareKdump
        # Make sure kdump service is finish loading kexec for panic (i.e. kexec -p)
        # So `kexec -l`` won't compete resources with kexec -p
        # Otherwise it may fail with: kexec_load failed: Device or resource busy
        if command -v kdumpctl &> /dev/null; then
            kdumpctl status &> /dev/null
        else
            service kdump status &> /dev/null
        fi

        # Prepare kexec cmd and run kexec load
        local _initrd_img_path _vmlinuz_path
        if stat /run/ostree-booted > /dev/null 2>&1; then
            _initrd_img_path=$(find $K_BOOT -name "${INITRD_PREFIX}-${KEXEC_VER}.img-*")
        else
            _initrd_img_path="$K_BOOT/$INITRD_PREFIX-${KEXEC_VER}.img"
        fi
        [ -z "${_initrd_img_path}" ] && {
            if "$IS_DB"; then
                # From 8.5, kdump will try using nondebug kernel/initramfs img if it's running on a debug kernel.
                Log "kdump initramfs img is only built for the nondebug kernel, not the debug kernel. Skip this test."
            else
                Error "Failed to find kdump initramfs img. Please check your kernel setup."
            fi
            return
        }

        _vmlinuz_path=$(ls ${K_BOOT}/vmlinuz-${KEXEC_VER}!(*debug*|*64k*|*rt*))
        [ -z "${_vmlinuz_path}" ] && _vmlinuz_path=$(ls ${K_BOOT}/vmlinux-${KEXEC_VER}!(*debug*|*64k*|*rt*))

        cmd="kexec ${EXTRA_KEXEC_OPTIONS} \
            -l ${_vmlinuz_path} \
            --initrd=${_initrd_img_path} \
            --command-line=\"$(cat /proc/cmdline) ${test_boot_option}\""

        Log "- Running cmd: ${cmd}"
        eval ${cmd} || {
            Error "kexec cmd returned a non-zero value."
            return
        }

        Log "- Loaded new kernel $KEXEC_VER."
        Log "- Switch to new kernel"
        # A system reboot after kexec -l call will kexec-switch to the loaded kernel.
        # Note, do not use rstrnt-reboot here as it will set next boot option affecting
        # next normal reboot instead this kexec reboot.
        reboot

    elif [ "$RSTRNT_REBOOTCOUNT" -eq $((init_reboot_count+1)) ]; then
        Log "Kexec Phase 2: Running on the kexec'd kernel"
        Log "- Current kernel and options are: "
        Log "$(uname -r)"
        Log "$(cat /proc/cmdline)"

        if grep -q "${test_boot_option}" < /proc/cmdline ; then
            Log "- Kexec boot to new kernel $KEXEC_VER successfully."
            Log "- Reboot to normal kernel"
            SafeReboot
        else
            Error "Kexec boot failed. Expect to see ${test_boot_option} in kernel boot options"
            return
        fi

    elif [ "$RSTRNT_REBOOTCOUNT" -eq $((init_reboot_count+2)) ]; then
        Log "Kexec Phase 3: Back to the normal kernel"
        Log "- Current kernel and options are: "
        Log "$(uname -r)"
        Log "$(cat /proc/cmdline)"
        Log "- Reboot back to normal kernel successfully."
    else
        Error "Unexpected reboot. Expect to reboot 2 times but detected reboot: $((RSTRNT_REBOOTCOUNT-init_reboot_count))."
    fi
}
