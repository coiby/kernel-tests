#!/bin/sh

# SPDX-License-Identifier: GPL-2.0-or-later
# Description: module_diff

# Source the common test script helpers
. ../../cki_lib/libcki.sh           || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

TESTAREA="/mnt/testarea"

# Variable used by beakerlib
export TEST="core-kernel/module_diff"

# Kernel Variables
K_NAME=`rpm -q --queryformat '%{name}\n' -qf /boot/config-$(uname -r)`
K_VER=`rpm -q --queryformat '%{version}\n' -qf /boot/config-$(uname -r)`
K_REL=`rpm -q --queryformat '%{release}\n' -qf /boot/config-$(uname -r)`
K_ARCH=$(rpm -q --queryformat '%{arch}' -f /boot/config-$(uname -r))

MODULE_PATH="/lib/modules"
Builtin_File='modules.builtin'

devnull=0

# Functions
function DeBug ()
{
    local msg=$1
    local timestamp=$(date '+%F %T')
    if [ "$devnull" = "0" ]; then
        (
            flock -x 200 2>/dev/null
            echo -n "${timestamp}: " 2>&1
            echo "${msg}"  2>&1
        )
    else
        echo "${msg}" > /dev/null 2>&1
    fi
}

# Functions

function GetVariant ()
{
    if [ ${ARCH} == "aarch64" ] && cki_is_kernel_rt && grep -q 64k <<< ${K_NAME}; then
        variant_name="rt-64k"
    elif cki_is_kernel_rt; then
        variant_name="rt"
    elif grep -q 64k <<< ${K_NAME}; then
        variant_name="64k"
    else
        variant_name=""
    fi
}

function GetVariantDebug ()
{
    if cki_is_kernel_debug && [ -n "$variant_name" ]; then
        variant_name+="-debug"
    elif cki_is_kernel_debug; then
        variant_name="debug"
    else
        variant_name=$variant_name
    fi
}

function GetCurrentModuleList ()
{
    # Lets determine the module list for the current kernel package

    # This is an example of getting a sorted list of available modules
    # rpm -q --filesbypkg kernel-2.6.32-220.el6 | grep '\.ko' | awk -F/ '{ print $NF }' | sort
    case $1 in
        loadable)
            local moduleList="moduleList_current"
            if [[ "${OS}" = "RHEL8" || "${OS}" = "RHEL9" || "${OS}" = "RHEL10" ]]; then
                PKG_LIST="${name}-modules-${K_VER}-${K_REL} ${name}-modules-extra-${K_VER}-${K_REL} ${name}-modules-core-${K_VER}-${K_REL} ${name}-core-${K_VER}-${K_REL}"
            else
                PKG_LIST="${name}-${K_VER}-${K_REL}"
            fi
            if cki_is_kernel_rt && rt_kvm_check; then
                PKG_LIST="${PKG_LIST} ${name}-kvm-${K_VER}-${K_REL}"
            fi
            rpm -q --filesbypkg $PKG_LIST | grep '\.ko' | awk -F/ '{ print $NF }' | sed 's/\.xz$//' | sort > ${TESTAREA}/${moduleList}
            ;;
        builtin)
            local moduleList="moduleList_builtin_current"
            local FILE="${MODULE_PATH}/$(uname -r)/${Builtin_File}"
            rm -rf ${TESTAREA:-"/mnt/testarea"}/${moduleList:-"empty"}
            touch ${TESTAREA}/${moduleList}
            while read line
            do
                echo ${line##*/}
            done < $FILE | sort >> ${TESTAREA}/${moduleList}
            ;;
    esac

    if [ ! -s "${TESTAREA}/${moduleList}" ]; then
        echo "" | tee -a $OUTPUTFILE
        DeBug "Unable to determine current $1 module list"
        cki_print_info "GetCurrentModuleList"
    fi

}

function AddDebug2List ()
{
    local debug_variant=$3
    cat ${TESTAREA}/$2 ./${OS}/${Release}/${Release}-${debug_variant}-$1-${ARCH}.lst | sort | uniq > ${TESTAREA}/${2}_temp
    \cp ${TESTAREA}/${2}_temp ${TESTAREA}/$2
}

function AddVariant2List ()
{
    local variant=$3
    if [ -n "$variant" ]; then
        cat ./${OS}/${Release}/${Release}{-,-${variant}-}$1-${ARCH}.lst | sort | uniq > ${TESTAREA}/${2}_temp
    else
        cat ./${OS}/${Release}/${Release}-$1-${ARCH}.lst | sort | uniq > ${TESTAREA}/${2}_temp
    fi
    \cp ${TESTAREA}/${2}_temp ${TESTAREA}/$2
}

function GetBaseModuleList ()
{
    # Lets determine the module list for the base release kernel package
    case $1 in
        loadable)
            local moduleList="moduleList_base"
            local listFile="modules"
            ;;
        builtin)
            local moduleList="moduleList_builtin_base"
            local listFile="builtin"
            ;;
    esac

    GetVariant
    AddVariant2List $listFile $moduleList $variant_name

    GetVariantDebug
    if cki_is_kernel_debug ; then
        AddDebug2List $listFile $moduleList $variant_name
    fi

    if [ ! -s "${TESTAREA}/${moduleList}" ]; then
        echo "" | tee -a $OUTPUTFILE
        DeBug "Unable to determine $1 base module list"
        cki_print_info "GetBaseModuleList"
    fi

}

function GetKnownRemovedList ()
{
    # Lets determine the "known removed" module list for the base release kernel package
    case $1 in
        loadable)
            local moduleList="moduleList_knownRemoved"
            local listFile="knownRemoved"
            ;;
        builtin)
            local moduleList="moduleList_builtin_knownRemoved"
            local listFile="knownRemoved-builtin"
            ;;
    esac

    # RHEL-6.0 and RHEL-7.0 have no "known removed" module list
    if [ "$Release" = "6.0" ] || [ "$Release" = "7.0" ] || [ "$Release" = "8.0" ]; then
        # Lets just create an empty file moduleList_knownRemoved for checking against RHEL-6.0 or RHEL-7.0
        touch ${TESTAREA}/${moduleList}
    else
        cat ./${OS}/${Release}/${Release}-${listFile}-${ARCH}.lst > ${TESTAREA}/${moduleList}
    fi

    GetVariant
    AddVariant2List ${listFile} ${moduleList} ${variant_name}
    GetVariantDebug
    if cki_is_kernel_debug ; then
        AddDebug2List $listFile $moduleList $variant_name

    fi
    if [ ! -e "${TESTAREA}/${moduleList}" ]; then
        DeBug "Unable to determine $1 known removed module list"
        cki_print_info "GetKnownRemovedModuleList"
    fi

}

function CrossCheck ()
{
    local TYPE=$1
    local FILE=$2
    if [ x"$TYPE" == "xloadable" ]; then
        for m in $(cat ${FILE})
        do
            if grep $m ${MODULE_PATH}/$(uname -r)/${Builtin_File} ; then
                sed -i "/^$m$/d" ${FILE}
                rlLog "$m change to built-in module"
            fi
        done
    elif [ x"$TYPE" == "xbuiltin" ]; then
        for m in $(cat ${FILE})
        do
            local MOD=$(find /lib/modules/`uname -r` -name "$m*")
            if grep "/$m" <<< ${MOD}; then
                sed -i "/^$m$/d" ${FILE}
                rlLog "$m change to loadable module"
           fi
        done
    fi
}

function CompareModuleList ()
{
    case $1 in
            loadable)
                    local moduleList="moduleList"
                    ;;
            builtin)
                    local moduleList="moduleList_builtin"
                    ;;
    esac
    # Lets submit the complete log from the diff of base module list and the current module list
    diff -u ${TESTAREA}/${moduleList}_base ${TESTAREA}/${moduleList}_current > ${TESTAREA}/${moduleList}_base-current_diff
    cp ${TESTAREA}/${moduleList}_base-current_diff ${TESTAREA}/${moduleList}_base-current_diff.log
    rlFileSubmit ${TESTAREA}/${moduleList}_base-current_diff.log ${moduleList}_base-current_diff.log

    #
    # Compared: Lets compare the base and current module lists
    #

    # Check new added modules
    diff -u ${TESTAREA}/${moduleList}_base ${TESTAREA}/${moduleList}_current | grep -e "^+" > ${TESTAREA}/${moduleList}_compare_added
    FileClean ${moduleList}_compare_added

    if [ ! -s ${TESTAREA}/${moduleList}_compare_added ]; then
        rlPass "New added modules check PASS"
    else
        cp ${TESTAREA}/${moduleList}_compare_added ${TESTAREA}/${moduleList}_compare_added.log
        rlFileSubmit ${TESTAREA}/${moduleList}_compare_added.log ${moduleList}_compare_added.log
        rlLogWarning "Existing new module(s), please check log: ${moduleList}_compare_added.log"
        echo "************New modules list start***************" | tee -a $OUTPUTFILE
        cat ${TESTAREA}/${moduleList}_compare_added | tee -a $OUTPUTFILE
        echo "************New modules list end*****************" | tee -a $OUTPUTFILE
        rlPass "Warn: existing new added modules"
    fi

    diff -u ${TESTAREA}/${moduleList}_base ${TESTAREA}/${moduleList}_current | grep -e "^-" > ${TESTAREA}/${moduleList}_compare

    # Lets clean up the format of our diff outputfile
    FileClean ${moduleList}_compare

    if [ ! -s "${TESTAREA}/${moduleList}_compare" ]; then
        # RHEL6 only: There is one final test for RHEL6
        if [ "${K_VER}" = "2.6.32" ]; then
                RHEL6_TestBZ839667 ${moduleList}
        fi

        # If we get here there are no missing modules
    fi

    #
    # Checked: Lets check against the "known removed" list
    #

    diff -u ${TESTAREA}/${moduleList}_compare ${TESTAREA}/${moduleList}_knownRemoved | grep -e "^-" > ${TESTAREA}/${moduleList}_missing

    # Lets clean up the format of our diff outputfile
    FileClean ${moduleList}_missing

    if [ -s "${TESTAREA}/${moduleList}_missing" ]; then
        # RHEL6 only: There is one final test for RHEL6
        if [ "${K_VER}" = "2.6.32" ]; then
            RHEL6_TestBZ839667
        fi

        CrossCheck $1 ${TESTAREA}/${moduleList}_missing
    fi

}

function ReportMissingModule ()
{
    case $1 in
            loadable)
                    local moduleList="moduleList"
                    ;;
            builtin)
                    local moduleList="moduleList_builtin"
                    ;;
    esac
    if [ ! -s "${TESTAREA}/${moduleList}_missing" ]; then
        return
    fi
    DisplayModuleFail ${moduleList}_missing
    cp ${TESTAREA}/${moduleList}_missing ${TESTAREA}/${moduleList}_missing.log
    rlFileSubmit ${TESTAREA}/${moduleList}_missing.log ${moduleList}_missing.log
    # report each missing module as individual result
    while IFS= read -r module
    do
        rlPhaseStartTest "Missing ${1} module ${module}"
            rlFail "The ${1} module ${module} is missing! Check ${moduleList}_missing.log for more details."
        rlPhaseEnd
    done < "${TESTAREA}/${moduleList}_missing.log"

}

function FileClean ()
{
    # Lets clean up the format of a diff outputfile
    # This allows for a clean list for the next comparison

    filename=$1

    # Remove the first line, as its a header not a module listing
    sed -i '1d' ${TESTAREA}/${filename}

    # Remove the "leading -" from each line, providing a new clean module listing
    sed -i 's/^-//;s/^+//' ${TESTAREA}/${filename}
}

function RHEL6_TestBZ839667 ()
{
    # RHEL6 only: This will be our final test for RHEL6
    # This function is to be sure we dont unintentionally remove the ipw2200.ko module
    # See: https://bugzilla.redhat.com/show_bug.cgi?id=839667

    echo "" | tee -a $OUTPUTFILE
    echo "***** Testing BZ839667: ${K_NAME}-${K_VER}-${K_REL}-${K_ARCH} *****" | tee -a $OUTPUTFILE
    moduleList=$1
    # The ipw2200.ko is only relevant to the following arches: i386 and x86_64
    if [ "${ARCH}" = "i386" ] || [ "${ARCH}" = "x86_64" ]; then

        # Lets see if ipw2200.ko is in the current module list
        cat ${TESTAREA}/${moduleList}_current | grep ipw2200.ko > ${TESTAREA}/${moduleList}_BZ839667

        if [ ! -s "${TESTAREA}/${moduleList}_BZ839667" ]; then
            # The ipw2200.ko module is missing from current module list
            # Lets see if the ipw2200.ko module is in the "known removed" modules list
            cat ${TESTAREA}/${moduleList}_knownRemoved | grep ipw2200.ko
            if [ "$?" -ne "0" ]; then
                # The ipw2200.ko module is _not_ in the "known removed" module list
                # This is a FAIL

                # Append the ipw2200.ko module to ${TESTAREA}/moduleList_missing
                echo "ipw2200.ko" >> ${TESTAREA}/moduleList_missing

                DisplayModuleFail ${moduleList}_missing
                cp ${TESTAREA}/${moduleList}_missing ${TESTAREA}/${moduleList}_missing.log
                rlFileSubmit ${TESTAREA}/${moduleList}_missing.log ${moduleList}_missing.log
                DeBug "RHEL6_TestBZ839667 fail"
                cki_print_info "RHEL6_TestBZ839667"
            fi

        fi
    fi
}

function DisplayModuleFail ()
{
    # Lets display the fail in a informative format

    file=$1

    echo "************ Missing modules list start ***********" | tee -a $OUTPUTFILE
    cat ${TESTAREA}/${file} | tee -a $OUTPUTFILE
    echo "************ Missing modules list end *************" | tee -a $OUTPUTFILE
}

# kernel-rt-kvm package no longer provided in 9.7 and 10.1
function rt_kvm_check ()
{
    if grep -q 'release 9' /etc/redhat-release; then
        cki_kver_ge "5.14.0-581.el9" && return 1 || return 0
    elif grep -q 'release 10' /etc/redhat-release; then
        cki_kver_ge "6.12.0-79.el10" && return 1 || return 0
    else
        return 0
    fi
}

function inst_kernel_rt_kvm ()
{
    rt_kvm="${name}-kvm-${K_VER}-${K_REL}.${K_ARCH}"
    local rpm_url="${url}/${rt_kvm}.rpm"
    rpm -q $rt_kvm || $YUM -y install $rt_kvm || $YUM -y install ${rpm_url}
    rpm -q $rt_kvm || cki_abort_task "Missing ${name}-kvm"

}

# Check if kernel{,-debug}-modules-extra installed
function chk_inst_kernel_modules_extra ()
{
    pkg_kms_extra="${name}-modules-extra-${K_VER}-${K_REL}.${K_ARCH}"
    local rpm_url="${url}/${pkg_kms_extra}.rpm"
    rpm -q $pkg_kms_extra > /dev/null || $YUM -y install $pkg_kms_extra || $YUM -y install ${rpm_url} || (cki_abort_task "Missing ${name}-modules-extra")
}
function chk_inst_kernel_modules_core ()
{
    pkg_kms_core="${name}-modules-core-${K_VER}-${K_REL}.${K_ARCH}"
    local rpm_url="${url}/${pkg_kms_core}.rpm"
    rpm -q $pkg_kms_core > /dev/null || $YUM -y install $pkg_kms_core || ($YUM -y install ${rpm_url} || cki_print_warning "Missing ${name}-modules-core, please check")
}


function SetOSRelease ()
{
    OS=""
    Release=""
    #
    # Base: Lets determine base release kernel package
    #
    Base=`echo ${K_REL} | cut -d. -f1`
    if [ "${K_VER}" = "2.6.32" ]; then
        # This is RHEL6 (Santiago)
        OS="RHEL6"
        case ${Base} in
            *)
                # Last stream on RHEL-6
                Release="HEAD-6.10"
                ;;
        esac
    elif [ "${K_VER}" = "3.10.0" ]; then
        # This is RHEL7 (Maipo)
        OS="RHEL7"
        case ${Base} in
            957)
                # RHEL-7.6
                Release="7.6"
                ;;
            1062)
                # RHEL-7.7
                Release="7.7"
                ;;
            *)
                # Last stream on RHEL-7
                Release="HEAD-7.9"
                ;;
        esac
    elif [ "${K_VER}" = "4.18.0" ]; then
        # This is RHEL8, Ootpa
        OS="RHEL8"
        case ${Base} in
            193)
                # RHEL-8.2
                Release="8.2"
                ;;
            305)
                # RHEL-8.4
                Release="8.4"
                ;;
            372)
                # RHEL-8.6
                Release="8.6"
                ;;
            477)
                # RHEL-8.8
                Release="8.8"
                ;;
            *)
                Release="HEAD-8.10"
                ;;
        esac
    elif [ "${K_VER}" = "5.14.0" ]; then
        # This is RHEL9
        OS="RHEL9"
        case ${Base} in
            70)
                # RHEL-9.0
                Release="9.0"
                ;;
            284)
                # RHEL-9.2
                Release="9.2"
                ;;
            427)
                Release="9.4"
                ;;
            503)
                Release="9.5"
                ;;
            570)
                Release="9.6"
                ;;
            *)
                # Still in developing phase, need to update in future.
                Release="HEAD-9.7"
                ;;
        esac
    elif [[ "${K_VER}" = "6.12.0" ]];then
        # RHEL10
        OS="RHEL10"
        case ${Base} in
            55)
                Release="10.0"
                ;;
            *)
                # RHEL-10.1, developing phase
                Release="HEAD-10.1"
                ;;
        esac
    elif [[ -n "$(echo ${K_NAME} | grep kernel-pegas)" && "${K_VER}" = "4.10.0" ]]; then
        DeBug "Base release is RHEL7/Pegas1, skipping test."
        OS="RHEL7"
        Release="Pegas1"
        cki_print_info "Skipped"
        exit 0
    else
        echo "" | tee -a $OUTPUTFILE
        echo "***** FAILED: *****" | tee -a $OUTPUTFILE
        echo "***** Unable to determine base release kernel package. *****" | tee -a $OUTPUTFILE
        DeBug "Unable to determine base release"
        cki_print_info "Base"
        exit 1
    fi
}

function kernel_is_rhel() {
    [[ "$K_REL" =~ \.el[67891] ]]
}

if ! kernel_is_rhel; then
    cki_beakerlib_skip_task "Non support release"
fi

rlJournalStart
    rlPhaseStartSetup
        YUM=$(cki_get_yum_tool)
        name="kernel"
        baseurl=${BASEURL:-}
        if cki_is_kernel_rt; then
            name="${name}-rt"
        fi
        if grep -q 64k <<< ${K_NAME}; then
            name="${name}-64k"
        fi
        if cki_is_kernel_debug; then
            name="${name}-debug"
        fi
        if cki_kver_lt "5.14.0-285.el9"; then
            path_name=$(sed "s/-debug//;s/-64k//" <<< ${name})
        else
            path_name=$(sed "s/-debug//;s/-64k//" <<< ${name%-rt*})
        fi
        # 9.6 and 10.0 kernel, not accurate kernel version
        if cki_kver_gt "5.14.0-565.el9" || cki_kver_gt "6.12.0-50.el10"; then
            path_name="kernel"
        fi
        url="${baseurl}/${path_name}/${K_VER}/${K_REL}/${K_ARCH}/"
        if  grep -q "release 9\|release 10" /etc/redhat-release ; then
            chk_inst_kernel_modules_extra
            chk_inst_kernel_modules_core
        elif grep -q "release 8" /etc/redhat-release ; then
            chk_inst_kernel_modules_extra
        fi
        if cki_is_kernel_rt && rt_kvm_check; then
            inst_kernel_rt_kvm
        fi

        echo "***** Currently running kernel: $(uname -r) *****" | tee -a $OUTPUTFILE
        SetOSRelease

        if [[ "$Release" == "8.4" ]]; then
            if cki_kver_lt "4.18.0-305.8.1.el8_4"; then
                sed -i "/pinctrl-emmitsburg\.ko/d"  ${OS}/${Release}/8.4-modules-${ARCH}.lst
            fi
            #known issue: bz1968381
            if cki_kver_lt "4.18.0-305.11.1.el8_4"; then
                sed -i "/dptf_power\.ko/d" ${OS}/${Release}/8.4-modules-${ARCH}.lst
            fi
            if cki_kver_lt "4.18.0-305.109.1.el8_4"; then
                sed -i "/nf_log_syslog.ko/d" ${OS}/${Release}/8.4-modules-${ARCH}.lst
                sed -i "/nf_log_arp.ko/d; /nf_log_bridge.ko/d; /nf_log_common.ko/d; \
                        /nf_log_ipv4.ko/d; /nf_log_ipv6.ko/d; /nf_log_netdev.ko/d" \
                        ${OS}/${Release}/8.4-knownRemoved-${ARCH}.lst
            fi
        fi

        if [[ "$Release" == "8.6" ]]; then
            # known issue: bz2129923
            if cki_kver_lt "4.18.0-372.32.1.el8_6"; then
                sed -i "/hpilo\.ko/d"  ${OS}/${Release}/8.6-modules-aarch64.lst
            fi
        fi

        if [[ "$Release" == "HEAD-8.10" ]]; then
            if cki_kver_lt "4.18.0-526.el8"; then
                sed -i "/ftdi-elan\.ko/d" ${OS}/${Release}/$Release-knownRemoved-${ARCH}.lst
            fi
            if cki_kver_lt "4.18.0-534.el8"; then
                sed -i "/mcryptd\.ko/d; /sha1-mb\.ko/d; /sha256-mb\.ko/d; /sha512-mb.ko\.ko/d" ${OS}/${Release}/$Release-knownRemoved-x86_64.lst
            fi
            if cki_kver_lt "4.18.0-536.el8"; then
                sed -i "/snd-soc-cs42l42.ko/d; /snd-soc-cs42l42-sdw.ko/d; /snd-soc-max98363.ko/d;
                        /snd-soc-rt712-sdca-dmic.ko/d" ${OS}/${Release}/$Release-modules-x86_64.lst
            fi
        fi

        if [[ "$Release" == "9.0" ]]; then
            if cki_kver_lt "5.14.0-70.30.1.el9_0"; then
                sed -i '/libarc4.ko/d' ${OS}/${Release}/$Release-knownRemoved-s390x.lst
                sed -i '/cifs_arc4.ko/d;/cifs_md4.ko/d;' ${OS}/${Release}/$Release-modules-${ARCH}.lst
            fi
        fi

        if [[ "$Release" == "9.6" ]]; then
            if cki_kver_lt "5.14.0-570.14.1.el9_6"; then
                sed -i "/x509_selftest.ko/d"  ${OS}/${Release}/${Release}-builtin-${ARCH}.lst
            fi
        fi

        if [[ "$Release" == "HEAD-9.7" ]]; then
            if cki_kver_lt "5.14.0-571.el9"; then
                sed -i "/intel-ishtp_eclite.ko/d;/intel-oaktrail.ko/d;/intel-plr_tpmi.ko/d;/intel-sdsi.ko/d;
                /intel-tpmi_power_domains.ko/d;/intel-vsec.ko/d;
                /intel-vsec_tpmi.ko/d"  ${OS}/${Release}/${Release}-modules-x86_64.lst
            fi
            if cki_kver_lt "5.14.0-598.el9"; then
                sed -i "/snd-amd-acpi-mach.ko/d; /snd-sof-intel-hda-sdw-bpt.ko/d"  ${OS}/${Release}/${Release}-modules-x86_64.lst
            fi
            if cki_kver_lt "5.14.0-599.el9"; then
                sed -i "/fwctl.ko/d; /mlx5_fwctl.ko/d; /tpm_svsm.ko/d"  ${OS}/${Release}/${Release}-modules-x86_64.lst
            fi
        fi

        if [[ "$Release" == "HEAD-10.1" ]]; then
            if cki_kver_lt "6.12.0-66.el10"; then
                sed -i "/pci-pwrctl-pwrseq.ko/d"  ${OS}/${Release}/${Release}-knownRemoved-aarch64.lst
                sed -i "/pci-pwrctrl-pwrseq.ko/d"  ${OS}/${Release}/${Release}-modules-aarch64.lst
            fi
            if cki_kver_lt "6.12.0-84.el10"; then
                sed -i "/snd-acp-sdw-mach.ko/d; /snd-soc-acpi-intel-sdca-quirks.ko/d; /snd-soc-sdca.ko/d;
                /snd-soc-rt721-sdca.ko/d; /snd-soc-rt-sdw-common.ko/d"  ${OS}/${Release}/${Release}-modules-x86_64.lst
            fi
            if cki_kver_lt "6.12.0-86.el10"; then
                sed -i "/raid6test.ko/d; /scsi_proto_test.ko/d"  ${OS}/${Release}/${Release}-knownRemoved-${ARCH}.lst
                sed -i "/mailbox-test.ko/d"  ${OS}/${Release}/${Release}-debug-knownRemoved-aarch64.lst
                sed -i "/ntb_msi_test.ko/d"  ${OS}/${Release}/${Release}-knownRemoved-x86_64.lst
            fi
            if cki_kver_lt "6.12.0-87.el10"; then
                sed -i "/cs_dsp.ko/d"  ${OS}/${Release}/${Release}-modules-{aarch64,ppc64le}.lst
            fi
            if cki_kver_lt "6.12.0-91.el10"; then
                sed -i "/cx231xx.ko/d;/cx2341x.ko/d;/cx25840.ko/d;/^tuner.ko$/d;
                /tveeprom.ko/d"  ${OS}/${Release}/${Release}-modules-${ARCH}.lst
            fi
            if cki_kver_lt "6.12.0-93.el10"; then
                sed -i "/iommufd_driver.ko/d"  ${OS}/${Release}/${Release}-builtin-${ARCH}.lst
            fi
            if cki_kver_lt "6.12.0-95.el10"; then
                sed -i "/typec_thunderbolt.ko/d; /tsm.ko/d"  ${OS}/${Release}/${Release}-modules-${ARCH}.lst
            fi
            if cki_kver_lt "6.12.0-96.el10"; then
                sed -i "/arm-cca-guest.ko/d; /tsm.ko/d"  ${OS}/${Release}/${Release}-modules-aarch64.lst
            fi
            if cki_kver_lt "6.12.0-98.el10"; then
                sed -i "/cirrus-qemu.ko/d; /drm_panel_backlight_quirks.ko/d"  ${OS}/${Release}/${Release}-modules-${ARCH}.lst
                sed -i "/drm_client_lib.ko/d" ${OS}/${Release}/${Release}-builtin-${ARCH}.lst
            fi
            if cki_kver_lt "6.12.0-107.el10"; then
                sed -i "/tpm_svsm.ko/d"  ${OS}/${Release}/${Release}-modules-x86_64.lst
            fi
            if cki_kver_lt "6.12.0-109.el10"; then
                sed -i "/iwlmld.ko/d"  ${OS}/${Release}/${Release}-modules-{x86_64,aarch64}.lst
                sed -i "/nvgrace-gpu-vfio-pci.ko/d"  ${OS}/${Release}/${Release}-modules-aarch64.lst
                sed -i "/hid_bpf.ko/d"  ${OS}/${Release}/${Release}-builtin-ppc64le.lst
            fi
            if cki_kver_lt "6.12.0-115.el10"; then
                sed -i "/cs_dsp.ko/d; /snd-hda-cirrus-scodec.ko/d"  ${OS}/${Release}/${Release}-knownRemoved-{aarch64,ppc64le}.lst
            fi
        fi
    rlPhaseEnd

    # -----------------------------------
    # --------   Start Test   -----------
    # -----------------------------------

    rlPhaseStartTest "Loadable module test"
        # The module list for the current kernel package
        GetCurrentModuleList loadable

        # The module list for the base release kernel package
        GetBaseModuleList loadable

        # The known removed module list for the base release kernel package
        GetKnownRemovedList loadable

        # Compare the base module list and the current module list
        CompareModuleList loadable
    rlPhaseEnd
    # ReportMissingModule should be out of rlPhaseStartTest as it uses rlPhaseStartTest in it.
    ReportMissingModule loadable

    if grep -q "$Release" builtin_list; then
        rlPhaseStartTest "Builtin module test"
            GetCurrentModuleList builtin
            GetBaseModuleList builtin
            GetKnownRemovedList builtin
            CompareModuleList builtin
        rlPhaseEnd
        # ReportMissingModule should be out of rlPhaseStartTest as it uses rlPhaseStartTest in it.
        ReportMissingModule builtin
    fi
rlJournalEnd

rlJournalPrintText
# EndFile
