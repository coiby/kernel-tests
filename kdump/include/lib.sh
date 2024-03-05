#!/bin/bash

export K_TESTAREA="/mnt/testarea"
export K_NFS="${K_TESTAREA}/KDUMP-NFS"
export K_PATH="${K_TESTAREA}/KDUMP-PATH"
export K_RAW="${K_TESTAREA}/KDUMP-RAW"
export K_RAID="${K_TESTAREA}/KDUMP-RAID"
export K_REBOOT="./KDUMP-REBOOT"
export K_NET_IFCFG="${K_TESTAREA}/KDUMP-CONFIG-NET"

export KDUMP_CONFIG="/etc/kdump.conf"
export KDUMP_SYS_CONFIG="/etc/sysconfig/kdump"
export FSTAB_FILE="/etc/fstab"
export K_NMCLI_PATH="/etc/NetworkManager/system-connections"
export K_SSH_CONFIG="${HOME}/.ssh/config"
export K_ID_RSA="${SSH_KEY:-/root/.ssh/kdump_id_rsa}"
export K_DEFAULT_PATH="/var/crash"

export K_NFSSERVER=${K_NFSSERVER:-""}
export K_VMCOREPATH=${K_VMCOREPATH:-""}

export NODEBUGINFO=${NODEBUGINFO:-true}
export NOKDUMPRD=${NOKDUMPRD:-true}
export UPGRADE_FC_KDUMP=${UPGRADE_FC_KDUMP:-false}

# bz1664239 Check unnecessay kdump initramfs img rebuild if needed.
export CHECK_INITRD_REBUILD=${CHECK_INITRD_REBUILD:-false}
export ALLOW_SKIP=${ALLOW_SKIP:-"true"}

# Output and based on which result will be reporting
export OUTPUTFILE
if [ -z "${OUTPUTFILE}" ]; then
    OUTPUTFILE=$(mktemp ${K_TESTAREA}/tmp.XXXXXX)
fi

# Set well-known logname so users can easily find
# current tasks log file.  This well-known file is also
# used by the local watchdog to upload the log
# of the current task.
if [ -h /mnt/testarea/current.log ]; then
    ln -sf "${OUTPUTFILE}" /mnt/testarea/current.log
else
    ln -s "${OUTPUTFILE}" /mnt/testarea/current.log
fi

function report_result {
    # Pass OUTPUTFILE to rstrnt-report-result in case the variable wasn't exported
    OUTPUTFILE="${OUTPUTFILE}" rstrnt-report-result "$@"
}


# Kernel Variables
export K_NAME K_ARCH K_VER K_REL K_KVARI K_SPEC_NAME

if [[ $(rpm -qf /boot/vmlinuz-"$(uname -r)") =~ "not owned by any package" ]]; then
    # kernel config/vmlinuz are installed from tarball, not dnf install
    # So far test only support "kernel" to be installed via tarball, not other variant.
    K_NAME=kernel
    K_ARCH=$(uname -m)
    K_VER=$(uname -r | cut -d'-' -f1)
    K_REL=$(uname -r | cut -d'-' -f2-)
    K_KVARI=$(uname -r | grep -Eo '(debug|rt|rt(-)*debug|64k|64k-debug)$')
    K_SPEC_NAME=kernel
else
    # Example outputs: kernel-core, kernel-rt-core, kernel-rt-debug-core
    K_NAME=$(rpm --queryformat '%{name}\n' -qf /boot/config-"$(uname -r)")
    K_ARCH=$(uname -m)

    # Kernel version
    # Example outputs: 2.6.32, 4.18.0
    K_VER=$(rpm --queryformat '%{version}\n' -qf /boot/config-"$(uname -r)")

    # Kernel release (version variant and arch)
    # Example outputs: 1160.81.1.el7, 226.el9, 5.14.0-226.rt14.227.el9
    K_REL=$(rpm --queryformat '%{release}\n' -qf /boot/config-"$(uname -r)")

    # Example outputs: debug, xen, vanilla
    # Note, rt kernel (and rt debug kernel) will be treated as variants after
    # rt kernel source is merged to kernel tree.
    K_KVARI=$(uname -r | grep -Eo '(debug|PAE|xen|trace|vanilla|rt|rt(-)*debug|64k|64k-debug)$')

    # Example output: kernel-2.6.32-220.el6.src.rpm
    K_SRC=$(rpm --queryformat '%{sourcerpm}\n' -qf /boot/config-"$(uname -r)")

    # Example outputs: kernel-rt, kernel
    # This is a little cryptic, in practice it takes the full src rpm file
    # name and strips everything after (including) the version, leaving just
    # the src rpm package name.
    # Needed
    # - when the kernel rpm comes from of e.g. kernel-pegas src rpm.
    # - kernel-rt rpm comes from kernel src rpm (merged source tree)
    K_SPEC_NAME=${K_SRC%%"-${K_VER}"*}
fi

export FAMILY RELEASE ARCH
export IS_RHEL5 IS_RHEL6 IS_RHEL7 IS_RHEL8 IS_RHEL9
export IS_FC IS_RHEL IS_COS
export IS_RT IS_DB IS_64K

if [ -z "$FAMILY" ]; then
    FAMILY=$(sed -e 's/\(.*\)release\s\([0-9]*\).*/\1\2/; s/\s//g' < /etc/redhat-release)
fi

[[ "$FAMILY" =~ [a-zA-Z]+5 ]] && IS_RHEL5=true || IS_RHEL5=false
[[ "$FAMILY" =~ [a-zA-Z]+6 ]] && IS_RHEL6=true || IS_RHEL6=false
[[ "$FAMILY" =~ [a-zA-Z]+7 ]] && IS_RHEL7=true || IS_RHEL7=false
[[ "$FAMILY" =~ [a-zA-Z]+8 ]] && IS_RHEL8=true || IS_RHEL8=false
[[ "$FAMILY" =~ [a-zA-Z]+9 ]] && IS_RHEL9=true || IS_RHEL9=false
[[ "$FAMILY" =~ Fedora ]] && IS_FC=true || IS_FC=false
[[ "$FAMILY" =~ CentOSStream ]] && IS_COS=true || IS_COS=false
[[ "$FAMILY" =~ RedHatEnterpriseLinux ]] && IS_RHEL=true || IS_RHEL=false

if $IS_FC || $IS_COS; then
    RELEASE=$(grep -o 'release [^ ]*' /etc/redhat-release  | awk '{print $NF}')
else
    RELEASE=$(grep -o 'release [^.]*' /etc/redhat-release | awk '{print $NF}')
fi

if [ -z "$ARCH" ]; then
    ARCH=$(uname -m)
fi

uname -r | grep -q rt && IS_RT=true || IS_RT=false
uname -r | grep -q "debug$" && IS_DB=true || IS_DB=false
uname -r | grep -q "+64k" && IS_64K=true || IS_64K=false

if $IS_RHEL5; then
    INITRD_PREFIX=initrd
    INITRD_KDUMP_PREFIX=initrd
elif $IS_RHEL6; then
    INITRD_PREFIX=initramfs
    INITRD_KDUMP_PREFIX=initrd
else
    INITRD_PREFIX=initramfs
    INITRD_KDUMP_PREFIX=initramfs
fi

export K_BOOT VMLINUZ_PATH
export INITRD_PREFIX INITRD_IMG_PATH
export INITRD_KDUMP_PREFIX INITRD_KDUMP_IMG_PATH

shopt -s extglob

if system_ostree; then
    K_BOOT="/usr/lib/ostree-boot"
    # kernel-automotive kernel and initramfs image on ostree contains a hash:
    # kernel image - vmlinuz-$(uname -r)-$(commit_hash)
    # initramfs image - initramfs-$(uname -r).img-${commit_hash}
    INITRD_IMG_PATH=$(find $K_BOOT -name "${INITRD_PREFIX}-$(uname -r).img-*")
    VMLINUZ_PATH=$(ls ${K_BOOT}/vmlinuz-"$(uname -r)"!(*debug*|*64k*|*rt*))
    [ -z "${VMLINUZ_PATH}" ] && VMLINUZ_PATH=$(ls ${K_BOOT}/vmlinux-"$(uname -r)"!(*debug*|*64k*|*rt*))
else
    [ "${K_ARCH}" = "ia64" ] && K_BOOT="/boot/efi/efi/redhat" || K_BOOT="/boot"
    INITRD_IMG_PATH="$K_BOOT/$INITRD_PREFIX-$(uname -r).img"
    VMLINUZ_PATH="${K_BOOT}/vmlinuz-$(uname -r)"
    [ -z "${VMLINUZ_PATH}" ] && VMLINUZ_PATH="${K_BOOT}/vmlinux-$(uname -r)"
fi

# Note, INITRD_KDUMP_IMG_PATH can be system initramfs img if fadump is enabled
INITRD_KDUMP_IMG_PATH=$(sed -e "s/\.img$/kdump.img/; s/$INITRD_PREFIX/$INITRD_KDUMP_PREFIX/" <<< "$INITRD_IMG_PATH")

if [ -s "/var/log/kdump.log" ]; then
    # From RHEL-8.7/9.1 kexec-tools will try using the nondebug kernel img if the file exists
    # So here we will try to retrieve the kdump img path from kdump.log.
    # kdump.log contains the exact kexec command called when starting the kdump service.
    tmp_img="$(grep /kexec /var/log/kdump.log | grep -Eo "initrd=.+ " | tail -n1 | cut -d'=' -f2)"
    [ -n "${tmp_img}" ] && INITRD_KDUMP_IMG_PATH="${tmp_img/ /}"
fi

# Backup kdump config files
BackupKdumpConfig(){
    [ -f "${KDUMP_CONFIG}" ] && [ ! -f "${KDUMP_CONFIG}.bk" ] && cp "${KDUMP_CONFIG}" "${KDUMP_CONFIG}.bk"
    [ -f "${KDUMP_SYS_CONFIG}" ] && [ ! -f "${KDUMP_SYS_CONFIG}.bk" ] && cp "${KDUMP_SYS_CONFIG}" "${KDUMP_SYS_CONFIG}.bk"
    [ -f "${FSTAB_FILE}.bk" ] || cp "${FSTAB_FILE}" "${FSTAB_FILE}.bk"
}

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
    if $IS_RHEL5 || $IS_RHEL6 ; then
        sed -i 's;\(/bin/sh\);\1 -x;' /etc/init.d/kdump
    else
        sed -i 's;\(/bin/sh\)$;\1 -x;' /usr/bin/kdumpctl
        sed -i 's;2>/dev/null;;g' /usr/bin/kdumpctl
    fi
}

GetBiosInfo()
{
    # Get BIOS information.
    rpm -q --quiet dmidecode || InstallPackages dmidecode
    dmidecode > "${K_TESTAREA}/bios.log"
    RhtsSubmit "${K_TESTAREA}/bios.log"
}

GetHWInfo()
{
    Log "Getting system hw or firmware config."
    rpm -q --quiet lshw || InstallPackages lshw
    CommandExists lshw && {
        lshw > "${K_TESTAREA}/lshw.output"
        RhtsSubmit "${K_TESTAREA}/lshw.output"
    }
    CommandExists lscfg  && {
        lscfg > "${K_TESTAREA}/lscfg.output"
        RhtsSubmit "${K_TESTAREA}/lscfg.output"
    }
}

FindModule()
{
    local name=$1

    #see if module was compiled in
    modname="$(modprobe -nv "$name" 2>/dev/null | grep "$name".ko)"
    if test -n "$modname"; then
        echo "$modname" | sed 's/insmod //'
        return
    fi

    #see if it was precompiled
    if test -f "$name/$name.ko"; then
        echo "$name/$name.ko"
        return
    fi

    #we have to create it
    echo ""
    return
}

MakeModule()
{
    CommandExists gcc || InstallDevTools

    local name=$1
    Log "Make module $name"
    mkdir "${name}"
    mv "${name}.c" "${name}"
    mv "Makefile.${name}" "${name}/Makefile"
    unset ARCH
    # if [ "${K_ARCH}" = "ppc64" ]; then
    #     Log "unset ARCH for ${K_ARCH}."
    #     unset ARCH
    # fi
    LogRun "make -C ${name}" || MajorError "Unable to compile ${name} Kernel module."
    ARCH="$(uname -m)"
}

InstallDevTools()
{
    #LogRun "yum groupinstall -y 'Development Tools'"

    #Workaround: RHEL 9 has problems installing group "'Development Tools".
    Log "Install development tools: kernel-devel elfutils-libelf-devel gcc"
    InstallPackages kernel-devel elfutils-libelf-devel gcc
}

InstallPackages()
{
    local action="install"
    if [ "${1,,}" = "upgrade" ]; then
        shift
        action=upgrade
    fi
    local pkgs="$*"

    [ $# -eq 0 ] && {
        Error "No package specified for ${action}ing"
        return 1
    }

    if system_ostree; then
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
    InstallPackages upgrade "$@"
}


# Install kernel related packages
InstallKernel()
{
    local pkgs="$*"
    local tmp=""

    [ ! -n "${pkgs}" ] && return 0

    Log "Install ${pkgs}"
    if system_ostree; then
        LogRun "rpm-ostree install --apply-live --allow-inactive --idempotent -y $pkgs"
    else
        if CommandExists dnf ; then
            LogRun "dnf install -y $pkgs"
        elif CommandExists yum ; then
            LogRun "yum install -y $pkgs"
        else
            return 1
        fi
    fi
    for i in ${pkgs}; do
        rpm -q --quiet "$i" || tmp="${tmp} $i"
    done
    [ -z "${tmp}" ] && return 0

    # If kernel is installed from tarball.
    # There is no way to get the corresponding packages from Brew/Koji
    [[ $(rpm -qf /boot/vmlinuz-"$(uname -r)") =~ "not owned by any package" ]] && {
        return 1
    }

    Log "Re-install missing packages from Brew/Koji."

    local brew_server=""
    local brew_baseurl=""
    if $IS_RHEL; then
        brew_server=download.devel.redhat.com
        brew_baseurl="http://$brew_server/brewroot/packages/${K_SPEC_NAME}"
    elif $IS_FC; then
        brew_server=kojipkgs.fedoraproject.org
        brew_baseurl="http://$brew_server/packages/${K_SPEC_NAME}"
    elif $IS_COS; then
        brew_server=cbs.centos.org
        brew_baseurl="http://$brew_server/kojifiles/packages/${K_SPEC_NAME}"
    else
        Log "Neither RHEL nor Fedora nor CentOS. System is not supported."
        return 1
    fi

    ping -q -c 5 "$brew_server" || {
        Log "Server $brew_server is not accessible"
        return 1
    }

    [ -d "temp" ] || mkdir temp > /dev/null
    local retval=0
    if pushd temp; then
        for i in ${tmp}; do
            Log "Downloading: ${brew_baseurl}/${K_VER}/${K_REL}/${K_ARCH}/${i}.rpm"
            curl -LO --fail "${brew_baseurl}/${K_VER}/${K_REL}/${K_ARCH}/${i}.rpm" 2> /dev/null || {
                retval=$?
                Log "Downloading ${i}.rpm failed"
                break
            }
        done
        popd || retval=1
    else
        retval=1
    fi

    if [ "${retval}" -eq 0 ]; then
        LogRun "rpm -Uvh --nodeps --force temp/*.rpm"
        retval=$?
    fi
    rm -f temp

    if [ "${retval}" -ne 0 ]; then
        Log "Failed to install missing packages from Brew/Koji."
        return 1
    fi
    return 0
}

# Install kernel debuginfo packages
InstallDebuginfo()
{
    # kernel name is kernel-core since rhel-8. So explicitly remove "-core"
    local kern comm
    kern=$(rpm -qf /boot/vmlinuz-"$(uname -r)" --qf "%{name}-debuginfo-%{version}-%{release}.%{arch}" | sed -e "s/-core//g")
    if [[ "$kern" =~ "not owned by any package" ]]; then
        # The kernel is installed from tarball, not rpm install
        kern="kernel-debuginfo-$(uname -r)"
        comm=""
    else
        # If RT kernel is not merged, the debuginfo common packge kernel-rt-debuginfo-common
        # If RT kernel is merged, the debuginfo common package should be kernel-debuginfo-common
        comm="${K_SPEC_NAME}-debuginfo-common-${K_ARCH}-${K_VER}-${K_REL}.${K_ARCH}"
        if $IS_RHEL5; then
            comm="${K_SPEC_NAME}-debuginfo-common-${K_VER}-${K_REL}.${K_ARCH}"
        fi
    fi

    rpm -q "${comm}" "${kern}" || InstallKernel "${comm}" "${kern}" || {
        Error "Failed to install kernel debuginfo packages"
        return 1
    }
    return 0
}

# Install Kpatch-patch debuginfo packages
InstallKpatchPatchDebuginfo()
{
    # Example of a kpatch-patch pkg "kpatch-patch-4_18_0-107-0-1.test.el8.x86_64"
    local kpp_pkg kpp_debuginfo_pkg
    kpp_pkg=$(rpm -qa | grep kpatch-patch | grep -v debug)
    [ -z "${kpp_pkg}" ] && Error "Failed to find kpatch-patch pkg"

    # Example of a kpatch-patch debuginfo pkg "kpatch-patch-4_18_0-107-debuginfo-0-1.test.el8.x86_64"
    kpp_debuginfo_pkg=$(echo "$kpp_pkg" | sed 's/-/-debuginfo-/4')

    # Kpatch-patch repo is supposed to be ready during test
    rpm -q "${kpp_debuginfo_pkg}" || {
        InstallPackages "${kpp_debuginfo_pkg}" || Error "Failed to install ${kpp_debuginfo_pkg}"
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

    if cki_is_abd; then
        action=add_aboot_param
    elif system_ostree; then
        action="--append-if-missing"
    else
        action="--args"
    fi
    if grep -q ^- <<< "${options}"; then
        if cki_is_abd; then
            action=remove_aboot_param
        elif system_ostree; then
            action="--delete-if-present"
        else
            action="--remove-args"
        fi
        options="$(sed "s/^-//" <<< "${options}")"
    fi

    {
        if cki_is_abd; then
            LogRun "${action} ${options}"
        elif system_ostree; then
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


CheckEnv()
{
    export SERVERFILE DEVMODE
    # Check test environment.
    if [ -z "${JOBID}" ]; then
        Log "Variable JOBID does not set! Assume developer mode."
        SERVERFILE="Server-$(date +%H_%j)"
        DEVMODE=true
    else
        SERVERFILE="Server-${JOBID}"
    fi
}

PrepareKdump()
{
    # install kdump package and related packages required for testing kdump functionalities.
    rpm -q --quiet kexec-tools || {
        InstallPackages kexec-tools || return 1
        LogRun "systemctl enable kdump.service" || LogRun "chkconfig kdump on"
        # Back up configurations if kexec-tools is installed for the first time
        BackupKdumpConfig
    }
    if $IS_FC && $UPGRADE_FC_KDUMP; then
        Log "[UPGRADE_FC_KDUMP=true] Upgrading kexec-tools dracut systemd on Fedora rawhide."
        UpgradePackages kexec-tools dracut systemd selinux-policy --enablerepo=updates-testing --enablerepo=fedora --releasever=rawhide

        #It's fine it fails to restart as on FC crashkernel is not reserved by default. Need futher updating kernel options.
        Log "Rebuild Kdump img in case dracut/systed updated"
        LogRun "kdumpctl rebuild; kdumpctl restart"
    fi
    return 0
}

PrepareCrash()
{
    Log "Prepare for crash tests"
    # install crash package and kernel-debuginfo required for testing crash untilities.
    rpm -q crash || InstallPackages crash || return 1

    if $IS_FC && $UPGRADE_FC_KDUMP; then
        Log "[UPGRADE_FC_KDUMP=true] Upgrading crash on Fedora rawhide."
        UpgradePackages crash --enablerepo=updates-testing --enablerepo=fedora --releasever=rawhide
    fi

    InstallDebuginfo
}

PrepareDrgn()
{
    Log "Prepare for drgn tests"
    # install crash package and kernel-debuginfo required for testing crash untilities.
    rpm -q drgn || InstallPackages drgn || return 1

    InstallDebuginfo
}


PrepareReboot()
{
    # IA-64 needs nextboot set.
    if [ -e "/usr/sbin/efibootmgr" ]; then
        EFI=$(efibootmgr -v | grep BootCurrent | awk '{ print $2}')
        if [ -n "$EFI" ]; then
            Log "Updating efibootmgr next boot option to $EFI according to BootCurrent"
            efibootmgr -n "$(efibootmgr -v | grep BootCurrent | awk '{ print $2}')"
        elif [[ -z "$EFI" && -f /root/EFI_BOOT_ENTRY.TXT ]] ; then
            os_boot_entry=$(</root/EFI_BOOT_ENTRY.TXT)
            Log "Updating efibootmgr next boot option to $os_boot_entry according to EFI_BOOT_ENTRY.TXT"
            efibootmgr -n "$os_boot_entry"
        else
            Log "Could not determine value for BootNext!"
        fi
    fi
}

RhtsReboot()
{
    Log "Rebooting..."
    rstrnt-reboot
}

SimpleReboot()
{
    Log "Rebooting..."
    reboot

    # Wait for the shutdown to kill us.  Sleep to avoid returning
    # control back to the test harness. ref: SIGTERM comments above
    while (true); do
        sleep 666
    done
}

# Run sub tests under testcases
RunSubTests(){
    TESTARGS=$1
    SKIP_TESTARGS=${2:-"NOEXISTCASE"}

    Log "================================="
    Log "  Test setup"
    Log "================================="

    TmpDir=$(mktemp -d -p .)
    cp -r testcases/* "$TmpDir"
    Log "Copy to tmp directory: ${TmpDir}"

    # Run tests specified in arg "TESTARGS". Otherwise run all sh scripts defined in
    # in subdirectory testcases. Tests specified in arg "SKIP_TESTARGS" will always be
    # skipped.
    # If multiple script names are provided in TESTARGS or SKIP_TESTARGS, script names
    # should be separated by comma.
    # if the arg "TESTARGS" is "all", run all sh scripts defined in subdirectory testcases
    # e.g. TESTARGS="analyse-crash-common.sh,analyse-crash-simple.sh"

    local all_tests
    all_tests=$(find testcases/ -name "*.sh" -printf "%f\n")
    # shellcheck disable=SC2086
    if [ "TEST${TESTARGS}" == "TEST" ] || [ ${TESTARGS,,} == "all" ]; then
        TESTARGS="all"
    else
        TESTARGS="$(echo "${TESTARGS}" | sed -r 's/[, ]+/|/g;s/\|+$//g;s/^\|+//g')"
    fi
    SKIP_TESTARGS="$(echo "${SKIP_TESTARGS}" | sed -r 's/[, ]+/|/g;s/\|+$//g;s/^\|+//g')"

    # Note, there is no handling of system reboot in this runtest.sh.
    for subcase in ${all_tests}; do
        tmp_subcase=$(basename "${subcase}")
        if [ "${TESTARGS,,}" != "all" ] && ! grep -E -q "${TESTARGS}" <<< "${tmp_subcase}"; then
            # Not in TESTARGS list.Ignore the test
            continue
        fi

        Log "============================================="
        Log "  #Sub Test# $subcase"
        Log "============================================="
        if grep -E -q "${SKIP_TESTARGS}" <<< "${tmp_subcase}"; then
            Log "Skip test: ${subcase}"
            continue
        elif [ ! -f "testcases/${subcase}" ]; then
            Warn "Skip test ${subcase}: No such file or directory"
            continue
        fi

        Log "Execute ${TmpDir}/${subcase}"
        sh "${TmpDir}/${subcase}"
    done

    Log "================================="
    Log "  Test cleanup"
    Log "================================="

    Log "Removing tmp directory $TmpDir"
    rm -rf "$TmpDir"

}

MultihostStage()
{
    local stage=$1; shift
    RunBeakerTest "$@"
    Report "$stage"
}

Multihost()
{
    RunBeakerTest "$@"
    Report
}

RunBeakerTest()
{
    local func=("$@")

    skip=0
    warn=0
    error=0
    CheckEnv

    # Run test differently depends on it's a single host test
    # or a multi-host test on a SERVER or a CLIENT

    if [ -z "${SERVERS}" ] && [ -z "${CLIENTS}" ]; then
        "${func[@]}"
    elif echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
        TEST="${TEST}/client"
        "${func[@]}"
        Log "Client finishes."
    elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
        TEST="${TEST}/server"
        # Do nothing.
        Log "Server finishes."
    else
        Error "Neither server nor client"
    fi
}


# testing case which forbidden by selinux can offer a selinux's module
# and this function will try to compile the module and load it into system

ByPassSelinux()
{
    local te_file=$1
    local mod_file=${te_file%.*}.mod
    local pp_file=${te_file%.*}.pp

    [[ ! -e $te_file ]] && { echo "$te_file" doesn\'t exist...;return 1; }

    checkmodule -M -m -o "$mod_file" "$te_file" || { echo checkmodule failed;return 1;}
    semodule_package -o "$pp_file" -m "$mod_file" || { echo semodule_package failed;return 1; }
    semodule -i "$pp_file" || { echo semodule failed;return 1; }

    return 0
}

RestartNetwork()
{
    # NetworkManager is buggy, use network service.
    service NetworkManager status --no-pager &&
        service NetworkManager stop &&
        chkconfig NetworkManager off

    # bz#903087
    export SYSTEMCTL_SKIP_REDIRECT=1

    chkconfig network on &&
        service network restart
}

# Check if secure boot is being enforced.
#
# Per Peter Jones, we need check efivar SecureBoot-$(the UUID) and
# SetupMode-$(the UUID), they are both 5 bytes binary data. The first four
# bytes are the attributes associated with the variable and can safely be
# ignored, the last bytes are one-byte true-or-false variables. If SecureBoot
# is 1 and SetupMode is 0, then secure boot is being enforced.
#
# SecureBoot-UUID won't always be set when securelevel is 1. For legacy-mode
# and uefi-without-seucre-enabled system, we can manually enable secure mode
# by writing "1" to securelevel. So check both efi var and secure mode is a
# more sane way.
#
# Assume efivars is mounted at /sys/firmware/efi/efivars.
isSecureBootEnforced()
{
    local secure_boot_file setup_mode_file
    local secure_boot_byte setup_mode_byte

    secure_boot_file=$(find /sys/firmware/efi/efivars -name "SecureBoot-*" 2>/dev/null)
    setup_mode_file=$(find /sys/firmware/efi/efivars -name "SetupMode-*" 2>/dev/null)

    if [ -f "$secure_boot_file" ] && [ -f "$setup_mode_file" ]; then
        # shellcheck disable=SC2086
        secure_boot_byte=$(hexdump -v -e '/1 "%d\ "' $secure_boot_file|cut -d' ' -f 5)
        # shellcheck disable=SC2086
        setup_mode_byte=$(hexdump -v -e '/1 "%d\ "' $setup_mode_file|cut -d' ' -f 5)

        if [ "$secure_boot_byte" = "1" ] && [ "$setup_mode_byte" = "0" ]; then
            return 0
        fi
    fi

    return 1
}

# Compare current pkg version with given version
# Return
#    255 if current version < given version
#    0 if current version = given version
#    1 if current version > given version
#    Error if the input doesn't fit the requirements
# Usage
#    VerCompare $pkg $version
#    VerCompare crash 4.11.12-200
# Version is expected to be given in format:
#      4.11.12-100

# Examples, with crash-8.0.0-6.el9 installed
# $ VerCompare crash 8.0.0-6.el
# Error: invalid input

# $ VerCompare crash 8.0.0-6.el9_1
# $ echo $?
# 255

# $ VerCompare crash 8.0.0-7.el9
# $ echo $?
# 255

# $ VerCompare crash 8.0.0-6.el9
# $ echo $?
# 0

# $ VerCompare crash 8.0.0-5.el9
# $ echo $?
# 1

VerCompare() {
    local pkg=$1

    # Return 'Error' if $pkg is not installed.
    rpm -q --quiet "$pkg" || {
        echo 'Error: invalid input'
        return 255
    }

    local targ_version=$2            # given pkg version
    local curr_version=""            # current version of package

    if [[ "$pkg" =~ ^(kernel|kernel-alt|kernel-rt)$ ]]; then
        curr_version="${K_VER}-${K_REL}"
    else
        curr_version=$(rpm -q "$pkg" --qf "%{version}-%{release}")
    fi

    local current
    local target
    if [[ $targ_version =~ el|fc ]]; then
        # for the input like crash 8.0.0-7.el9
        local regex='^(.+)(\.el|\.fc)(.+)'
        # divide current version
        [[ $curr_version =~ $regex ]] || {
            echo 'Error: invalid input'
            return 255
        }
        current=("${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}")
        # divide target version
        [[ $targ_version =~ $regex ]] || {
            echo 'Error: invalid input'
            return 255
        }
        target=("${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}")
    else
        # for the input like crash 4.11.12-200 without el|fc suffix
        current=("$curr_version")
        target=("$targ_version")
    fi

    local curr_arr
    local targ_arr
    local OLDIFS=$IFS

    for index in ${!current[*]}; do
        IFS='.-_' read -r -a curr_arr <<<"${current[$index]}"
        IFS='.-_' read -r -a targ_arr <<<"${target[$index]}"
        local length=$((${#targ_arr[@]} > ${#curr_arr[@]} ? ${#targ_arr[@]} : ${#curr_arr[@]}))
        IFS=$OLDIFS

        for ((i = 0; i < $length; i++)); do
            [[ -z ${curr_arr[$i]} ]] && return 255
            [[ -z ${targ_arr[$i]} ]] && return 1

            [[ ${curr_arr[$i]} -lt ${targ_arr[$i]} ]] && return 255
            [[ ${curr_arr[$i]} -gt ${targ_arr[$i]} ]] && return 1
        done
    done
    return 0
}

# @usage: CheckSkipTest <pkg_name> <target_version>
# @description: Check whether to skip current test. When ALLOW_SKIP is true
#               and current pkg version is lower than target version, it returns
#               0 which means test can be skipped. If current pkg
#               version is equal or higher than target version, it returns 1
#               which means test should not be skipped.
# @param1: pkg  # name of pkg should be checked against
# @param2: version  # target version which current pkg version will be compared
#                     with.
CheckSkipTest()
{
    local pkg=$1
    local version=$2
    local checkOnly=${3:-'notcheckonly'} # Do no report Skip, check version only

    if [ "$ALLOW_SKIP" = "true" ]; then
        local err
        local retval
        err=$(VerCompare "$pkg" "$version")
        retval=$?

        [ "$err" = "Error: invalid input" ] && return 1
        [ "$retval" -ne 255 ] && return 1

        if [ "${checkOnly,,}" != "checkonly" ]; then
            Skip "Skip this test as current ${pkg} is lower than ${pkg}-${version}"
        fi
        return 0
    else
        return 1
    fi
}

# @usage: CheckUnexpectedReboot
# @description: Check whether system was rebooted unexpected. This is used for
# test cases that not testing system panic. e.g. system configuration or runing
# a crash analysis against a vmcore or live system.
# Test case which calls CheckUnexpectedReboot will be terminiated as FAIL if
# unexpected reboot is detected.
CheckUnexpectedReboot()
{
    count=${1:-"0"}
    if [ -n "$RSTRNT_" ] && [ "$RSTRNT_" -gt "$count" ]; then
        MajorError "Unexpected reboot is detected. Please check if system has \
been rebooted from panic or other possible incidents."
    fi
}

CommandExists()
{
    local cmd=$1
    if [ -z "$cmd" ]; then
        return 1
    elif which "$cmd" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}


# ---------- Logging ------------ #

((KD_LOG_SH)) && return || KD_LOG_SH=1

declare -i error warn skip

GetLogPrefix() {
    local timestamp
    timestamp=$(date +%H:%M:%S)
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
    echo -e "$(GetLogPrefix RUN)# $1" | tee -a "${OUTPUTFILE}"
    eval "${1}" | tee -a "${OUTPUTFILE}"
    local ret=${PIPESTATUS[0]}
    return "${ret}"
}

Skip() {
    echo -e "$(GetLogPrefix SKIP)$1" | tee -a "${OUTPUTFILE}"
    skip=$((skip + 1))
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
        rstrnt-sync-set -s "DONE"
    fi
    Report
}

# fatal error occurs - must abort recipe set
FatalError() {
    echo -e "$(GetLogPrefix FATAL)$1" | tee -a "${OUTPUTFILE}"
    echo -e "$(GetLogPrefix FATAL)Aborting the recipe set" | tee -a "${OUTPUTFILE}"

    error=$((error + 1))
    report_result "${TEST}" "FAIL" "${error}"
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
    echo -e ":: RESULT: ${result} (skip: ${skip:-0} warn: ${warn:-0} error: ${error:-0})"
    echo ":::::::::::::::::::::::::::::::::::::::::::::"

    #reset codes to avoid propogating them
    error=0
    warn=0
    skip=0

    if [ -n "${stage}" ]; then
        report_result "${stage}" "${result}" "${code}"
    else
        report_result "${TEST}" "${result}" "${code}"
        exit 0
    fi
}

# Upload system logs
# Params:
#   $1: Uploading logs of the specific service only
UploadJournalLogs() {
    local service="${1:-""}"
    local file_name="journal.log"
    local extra_cmd=""

    [ -n "${service}" ] && {
        file_name="journal-${service}.log"
        extra_cmd="-u ${service}"
    }

    if CommandExists journalctl ; then
        rm -f "${file_name}"
        journalctl -b "${extra_cmd}" > "${file_name}"
        RhtsSubmit "$(pwd)/${file_name}"
        sync
    else
        RhtsSubmit "/var/log/messages"
        sync
    fi

}

RhtsSubmit() {
    local size
    size=$(wc -c < "$1")
    # zip and upload the zipped file if the size of which is larger than 100M
    if [ "$size" -ge 100000000 ]; then
        Log "Size of File $1 is larger than 100M. Uploading the zipped file."
        zip "${1}.zip" "${1}"
        Log "Uploading ${1}.zip"
        rstrnt-report-log -l "${1}.zip" > /dev/null
    else
        Log "Uploading ${1}"
        rstrnt-report-log -l "${1}" > /dev/null
    fi
}


# @usage: GetCrashkernelDefault [rhel_version]
# @description: Get the crash kernel default value from the pre-defined json file based on arches and rhel version
#               Function will decrease the y-stream number until 0 if function doesn't find the request rhel version
#               e.g. If json file doesn't have RHEL-8.6, it will try to find it on 8.5 unitl 8.0
# @param1: rhel_version # the specific rhel version e.g. RHEL-8.6
#                         Note with param1 function will return error if it cannot find request rhel version from json file
#                         rather than decrease the y-stream number
# shellcheck disable=SC2120
GetCrashkernelDefault() {

    rpm -q --quiet jq || InstallPackages jq

    # Load current rhel version from /etc/os-release file
    source /etc/os-release
    local version_array=(${VERSION_ID//./ })

    local crashkernel_default="../include/crashkernel-default.json"
    local cmd_line=""
    local status
    local rhel_version

    while true; do
        rhel_version=${1:-"RHEL-${version_array[0]}.${version_array[1]}"}
        if [ "${K_ARCH}" = "ppc64le" ]; then
            if grep -q -e "fadump=on" -e "fadump=nocma" < /proc/cmdline; then
                # shellcheck disable=SC2086
                cmd_line=$(jq -r '.['\"$rhel_version\"']['\"$K_ARCH\"']["fadump"]' $crashkernel_default)
            else
                # shellcheck disable=SC2086
                cmd_line=$(jq -r '.['\"$rhel_version\"']['\"$K_ARCH\"']["kdump"]' $crashkernel_default)
            fi
        else
            # shellcheck disable=SC2086
            cmd_line=$(jq -r '.['\"$rhel_version\"']['\"$K_ARCH\"']' $crashkernel_default)
        fi
        status=$?

        # Will not continue if has a specific rhel version for $1
        [[ -n $1 ]] && break

        # return for the first not null result
        [[ "$cmd_line" != "null" ]] && break

        # Will decrease the y-stream number until 0
        # e.g. If json file doesn't have RHEL-8.6, it will try to find it on 8.5 unitl 8.0
        [[ "${version_array[1]}" -le 0 ]] && break

        # Decrase y-stream number by 1
        version_array[1]=$((${version_array[1]} - 1))

    done

    [[ $status -ne 0 || "$cmd_line" == "null" ]] && {
        Error "Cannot load RHEL-$VERSION_ID from crashkernel default json file, please check the parameter or json file"
        return 1
    }
    echo "$cmd_line"
}

ResetCrashkernel() {
    _fadump_opts=$1
    if cki_is_abd; then
        LogRun "add_aboot_param crashkernel=$(GetCrashkernelDefault)" && \
            _reboot_required=true
    else
        LogRun "kdumpctl reset-crashkernel ${_fadump_opts} 2>&1 | grep -i reboot" && \
            _reboot_required=true
    fi
}
