#!/bin/sh

# SPDX-License-Identifier: GPL-2.0-or-later
# Description: module_diff

# Source the common test script helpers
. ../../cki_lib/libcki.sh           || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

TESTAREA="/mnt/testarea"

# Kernel Variables
K_NAME=`rpm -q --queryformat '%{name}\n' -qf /boot/config-$(uname -r)`
#   example output: kernel
K_VER=`rpm -q --queryformat '%{version}\n' -qf /boot/config-$(uname -r)`
#   example output: 2.6.32
K_VARIANT=$(echo $K_NAME | sed -e "s/kernel//g")
#   are we a DEBUG kernel?
K_REL=`rpm -q --queryformat '%{release}\n' -qf /boot/config-$(uname -r)`
K_ARCH=$(rpm -q --queryformat '%{arch}' -f /boot/config-$(uname -r))

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

function GetCurrentModuleList ()
{
    # Lets determine the module list for the current kernel package

    echo "" | tee -a $OUTPUTFILE
    echo "***** Determining current module list: ${K_RUNNING} *****" | tee -a $OUTPUTFILE

    # This is an example of getting a sorted list of available modules
    # rpm -q --filesbypkg kernel-2.6.32-220.el6 | grep '\.ko' | awk -F/ '{ print $NF }' | sort

    if [ "${OS}" = "RHEL8" -o "${OS}" = "RHEL9" ]; then
        PKG_LIST="${name}-modules-${K_VER}-${K_REL} ${name}-modules-extra-${K_VER}-${K_REL} ${name}-modules-core-${K_VER}-${K_REL} ${name}-core-${K_VER}-${K_REL}"
        if $(cki_is_kernel_rt); then
            PKG_LIST="${PKG_LIST} ${name}-kvm-${K_VER}-${K_REL}"
        fi
    else
        PKG_LIST="${name}-${K_VER}-${K_REL}"
        if $(cki_is_kernel_rt); then
            PKG_LIST="${PKG_LIST} ${name}-kvm-${K_VER}-${K_REL}"
        fi
    fi
    rpm -q --filesbypkg $PKG_LIST | grep '\.ko' | awk -F/ '{ print $NF }' | sed 's/\.xz$//' | sort > ${TESTAREA}/moduleList_current

    if [ ! -s "${TESTAREA}/moduleList_current" ]; then
        echo "" | tee -a $OUTPUTFILE
        echo "***** FAILED: *****" | tee -a $OUTPUTFILE
        echo "***** Unable to determine current module list. *****" | tee -a $OUTPUTFILE
        DeBug "Unable to determine current module list"
        cki_print_info "GetCurrentModuleList"
    fi

    echo "***** Stored current module list: ${TESTAREA}/moduleList_current *****" | tee -a $OUTPUTFILE
}

function AddDebugKernelModuleToBase ()
{
    cat ./${OS}/${Release}/${Release}{-,-debug-}modules-${ARCH}.lst | sort | uniq > ${TESTAREA}/moduleList_base_debug
    \cp ${TESTAREA}/moduleList_base_debug ${TESTAREA}/moduleList_base
}

function AddRTBaseList ()
{
    if [ -f ./${OS}/${Release}/${Release}-rt-modules-${ARCH}.lst ]; then
        cat ./${OS}/${Release}/${Release}{-,-rt-}modules-${ARCH}.lst | sort | uniq > ${TESTAREA}/moduleList_base_rt
        \cp ${TESTAREA}/moduleList_base_rt ${TESTAREA}/moduleList_base
    fi
}

function AddRTnDebugBaseList ()
{
    cat ${TESTAREA}/moduleList_base_debug ./${OS}/${Release}/${Release}-rt-modules-${ARCH}.lst | sort | uniq > ${TESTAREA}/moduleList_base_rt
    \cp ${TESTAREA}/moduleList_base_rt ${TESTAREA}/moduleList_base
}

function GetBaseModuleList ()
{
    # Lets determine the module list for the base release kernel package

    echo "" | tee -a $OUTPUTFILE
    echo "***** Determining base module list: RHEL-${Release}-${ARCH} *****" | tee -a $OUTPUTFILE

    cat ./${OS}/${Release}/${Release}-modules-${ARCH}.lst > ${TESTAREA}/moduleList_base

    if $(cki_is_kernel_debug); then
        AddDebugKernelModuleToBase
        if $(cki_is_kernel_rt); then
            AddRTnDebugBaseList
        fi
    else
        if $(cki_is_kernel_rt); then
            AddRTBaseList
        fi
    fi

    if [ ! -s "${TESTAREA}/moduleList_base" ]; then
        echo "" | tee -a $OUTPUTFILE
        echo "***** FAILED: *****" | tee -a $OUTPUTFILE
        echo "***** Unable to determine base module list. *****" | tee -a $OUTPUTFILE
        DeBug "Unable to determine base module list"
        cki_print_info "GetBaseModuleList"
    fi

    echo "***** Stored base module list: ${TESTAREA}/moduleList_base *****" | tee -a $OUTPUTFILE
}

# Workround for RT
function AddRTKnowRemovedList ()
{
    cat ./${OS}/${Release}/${Release}{-,-rt-}knownRemoved-${ARCH}.lst | sort | uniq > ${TESTAREA}/moduleList_knownRemoved-rt
    \cp ${TESTAREA}/moduleList_knownRemoved-rt ${TESTAREA}/moduleList_knownRemoved
}
# Workround for aarch64 64k
function Add64kKnowRemovedList ()
{
    cat ./${OS}/${Release}/${Release}{-,-64k-}knownRemoved-${ARCH}.lst | sort | uniq > ${TESTAREA}/moduleList_knownRemoved-64k
    \cp ${TESTAREA}/moduleList_knownRemoved-64k ${TESTAREA}/moduleList_knownRemoved
}

function GetKnownRemovedList ()
{
    # Lets determine the "known removed" module list for the base release kernel package

    echo "" | tee -a $OUTPUTFILE
    echo "***** Determining known removed module list: RHEL-${Release}-${ARCH} *****" | tee -a $OUTPUTFILE

    # RHEL-6.0 and RHEL-7.0 have no "known removed" module list
    if [ "$Release" = "6.0" ] || [ "$Release" = "7.0" ] || [ "$Release" = "8.0" ]; then
        # Lets just create an empty file moduleList_knownRemoved for checking against RHEL-6.0 or RHEL-7.0
        touch ${TESTAREA}/moduleList_knownRemoved
    else
        cat ./${OS}/${Release}/${Release}-knownRemoved-${ARCH}.lst > ${TESTAREA}/moduleList_knownRemoved
    fi

    if $(cki_is_kernel_rt); then
        AddRTKnowRemovedList
    fi
    if $(cki_is_kernel_64k); then
        Add64kKnowRemovedList
    fi

    if [ ! -e "${TESTAREA}/moduleList_knownRemoved" ]; then
        echo "" | tee -a $OUTPUTFILE
        echo "***** FAILED: *****" | tee -a $OUTPUTFILE
        echo "***** Unable to determine known removed module list. *****" | tee -a $OUTPUTFILE
        DeBug "Unable to determine known removed module list"
        cki_print_info "GetKnownRemovedModuleList"
    fi

    echo "***** Stored "known removed" module list: ${TESTAREA}/moduleList_knownRemoved *****" | tee -a $OUTPUTFILE
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

    # The ipw2200.ko is only relevant to the following arches: i386 and x86_64
    if [ "${ARCH}" = "i386" ] || [ "${ARCH}" = "x86_64" ]; then

        # Lets see if ipw2200.ko is in the current module list
        cat ${TESTAREA}/moduleList_current | grep ipw2200.ko > ${TESTAREA}/moduleList_BZ839667

        if [ ! -s "${TESTAREA}/moduleList_BZ839667" ]; then
            # The ipw2200.ko module is missing from current module list
            # Lets see if the ipw2200.ko module is in the "known removed" modules list
            cat ${TESTAREA}/moduleList_knownRemoved | grep ipw2200.ko
            if [ "$?" -ne "0" ]; then
                # The ipw2200.ko module is _not_ in the "known removed" module list
                # This is a FAIL

                # Append the ipw2200.ko module to ${TESTAREA}/moduleList_missing
                echo "ipw2200.ko" >> ${TESTAREA}/moduleList_missing

                DisplayModuleFail moduleList_missing
                cp ${TESTAREA}/moduleList_missing ${TESTAREA}/moduleList_missing.log
                cki_upload_log_file ${TESTAREA}/moduleList_missing.log
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

    echo "" | tee -a $OUTPUTFILE
    echo "***** FAILED: *****" | tee -a $OUTPUTFILE
    echo "***** There are missing modules! *****" | tee -a $OUTPUTFILE
    echo "**************************************" | tee -a $OUTPUTFILE
    cat ${TESTAREA}/${file} | tee -a $OUTPUTFILE
    echo "**************************************" | tee -a $OUTPUTFILE
}

function inst_kernel_rt_kvm ()
{
    rt_kvm="${name}-kvm-${version}-${release}.${arch}"
    rpm -q $rt_kvm || $YUM -y install $rt_kvm || (cki_abort_task "Missing ${name}-kvm")

}

# Check if kernel{,-debug}-modules-extra installed
function chk_inst_kernel_modules_extra ()
{
    pkg_kms_extra="${name}-modules-extra-${version}-${release}.${arch}"
    rpm -q $pkg_kms_extra || $YUM -y install $pkg_kms_extra || (cki_abort_task "Missing ${name}-modules-extra")
}
function chk_inst_kernel_modules_core ()
{
    pkg_kms_core="${name}-modules-core-${version}-${release}.${arch}"
    rpm -q $pkg_kms_core || $YUM -y install $pkg_kms_core || (cki_print_warning "Missing ${name}-modules-core, please check")
}

rlJournalStart
    rlPhaseStartTest
        YUM=$(cki_get_yum_tool)
        name="kernel"
        arch=$(uname -m)
        version_release=`uname -r | sed "s/\.$K_ARCH//;s/+debug//;s/\.debug//;s/+64k//"`
        version=${version_release%-*}
        release=${version_release#*-}
        kvari=`uname -r | grep -Eo '(debug|PAE|xen)$'`
        if $(cki_is_kernel_rt); then
            name="${name}-rt"
        fi
        if $(cki_is_kernel_64k); then
            name="${name}-64k"
        fi
        if $(cki_is_kernel_debug); then
            name="${name}-debug"
        fi

        if  grep -q "release 9" /etc/redhat-release ; then
            chk_inst_kernel_modules_extra
            chk_inst_kernel_modules_core
        elif grep -q "release 8" /etc/redhat-release ; then
            chk_inst_kernel_modules_extra
        fi
        if $(cki_is_kernel_rt); then
            inst_kernel_rt_kvm
        fi
        # -----------------------------------
        # --------   Start Test   -----------
        # -----------------------------------

        echo "" | tee -a $OUTPUTFILE
        echo "***** Start of runtest.sh *****" | tee -a $OUTPUTFILE
        echo "" | tee -a $OUTPUTFILE
        echo "***** Currently running kernel: ${K_RUNNING} *****" | tee -a $OUTPUTFILE

        #
        # Base: Lets determine base release kernel package
        #
        Base=`echo ${K_REL} | cut -d. -f1`
        if [ "${K_VER}" = "2.6.32" ]; then
            # This is RHEL6 (Santiago)
            OS="RHEL6"
            case ${Base} in
                71)
                    # RHEL-6.0
                    DeBug "Base release is RHEL-6.0"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.0 *****" | tee -a $OUTPUTFILE
                    Release="6.0"
                    ;;
                131)
                    # Actual RHEL-6.1 is 131.0.15, but 131 will suffice for this case.
                    DeBug "Base release is RHEL-6.1"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.1 *****" | tee -a $OUTPUTFILE
                    Release="6.1"
                    ;;
                220)
                    # RHEL-6.2
                    DeBug "Base release is RHEL-6.2"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.2 *****" | tee -a $OUTPUTFILE
                    Release="6.2"
                    ;;
                279)
                    # RHEL-6.3
                    DeBug "Base release is RHEL-6.3"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.3 *****" | tee -a $OUTPUTFILE
                    Release="6.3"
                    ;;
                358)
                    # RHEL-6.4
                    DeBug "Base release is RHEL-6.4"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.4 *****" | tee -a $OUTPUTFILE
                    Release="6.4"
                    ;;
                431)
                    # RHEL-6.5
                    DeBug "Base release is RHEL-6.5"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.5 *****" | tee -a $OUTPUTFILE
                    Release="6.5"
                    ;;
                504)
                    # RHEL-6.6
                    DeBug "Base release is RHEL-6.6"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.6 *****" | tee -a $OUTPUTFILE
                    Release="6.6"
                    ;;
                573)
                    # RHEL-6.7
                    DeBug "Base release is RHEL-6.7"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.7 *****" | tee -a $OUTPUTFILE
                    Release="6.7"
                    ;;
                642)
                    # RHEL-6.8
                    DeBug "Base release is RHEL-6.8"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.8 *****" | tee -a $OUTPUTFILE
                    Release="6.8"
                    ;;
                696)
                    # RHEL-6.9
                    DeBug "Base release is RHEL-6.9"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-6.9 *****" | tee -a $OUTPUTFILE
                    Release="6.9"
                    ;;
                *)
                    # We are currently developing RHEL-6.10
                    # Therefore we test at HEAD-RHEL-6.10
                    DeBug "Base release is HEAD RHEL-6.10"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is HEAD-RHEL-6.10 *****" | tee -a $OUTPUTFILE
                    Release="HEAD-6.10"
                    ;;
            esac
        elif [ "${K_VER}" = "3.10.0" ]; then
            # This is RHEL7 (Maipo)
            OS="RHEL7"
            case ${Base} in
                123)
                    # RHEL-7.0
                    DeBug "Base release is RHEL-7.0"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.0 *****" | tee -a $OUTPUTFILE
                    Release="7.0"
                    ;;
                229)
                    # RHEL-7.1
                    DeBug "Base release is RHEL-7.1"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.1 *****" | tee -a $OUTPUTFILE
                    Release="7.1"
                    ;;

                327)
                    # RHEL-7.2
                    DeBug "Base release is RHEL-7.2"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.2 *****" | tee -a $OUTPUTFILE
                    Release="7.2"
                    ;;
                514)
                    # RHEL-7.3
                    DeBug "Base release is RHEL-7.3"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.3 *****" | tee -a $OUTPUTFILE
                    Release="7.3"
                    ;;
                693)
                    # RHEL-7.4
                    DeBug "Base release is RHEL-7.4"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.4 *****" | tee -a $OUTPUTFILE
                    Release="7.4"
                    ;;
                862)
                    # RHEL-7.5
                    DeBug "Base release is RHEL-7.5"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.5 *****" | tee -a $OUTPUTFILE
                    Release="7.5"
                    ;;
                957)
                    # RHEL-7.6
                    DeBug "Base release is RHEL-7.6"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.6 *****" | tee -a $OUTPUTFILE
                    Release="7.6"
                    ;;
                1062)
                    # RHEL-7.7
                    DeBug "Base release is RHEL-7.7"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.7 *****" | tee -a $OUTPUTFILE
                    Release="7.7"
                    ;;
                1127)
                    # RHEL-7.8
                    DeBug "Base release is RHEL-7.8"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-7.8 *****" | tee -a $OUTPUTFILE
                    Release="7.8"
                    ;;

                *)
                    # We are currently developing RHEL-7.9
                    # Therefore we test at HEAD-RHEL-7.9
                    DeBug "Base release is HEAD-RHEL-7.9"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is HEAD-RHEL-7.9 *****" | tee -a $OUTPUTFILE
                    Release="HEAD-7.9"
                    ;;
            esac
        elif [ "${K_VER}" = "4.18.0" ]; then
            # This is RHEL8, Ootpa
            OS="RHEL8"
            case ${Base} in
                80)
                    # RHEL-8.0
                    DeBug "Base release is RHEL-8.0"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.0 *****" | tee -a $OUTPUTFILE
                    Release="8.0"
                    ;;
                147)
                    # RHEL-8.1
                    DeBug "Base release is RHEL-8.1"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.1 *****" | tee -a $OUTPUTFILE
                    Release="8.1"
                    ;;
                193)
                    # RHEL-8.2
                    DeBug "Base release is RHEL-8.2"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.2 *****" | tee -a $OUTPUTFILE
                    Release="8.2"
                    ;;
                240)
                    # RHEL-8.3
                    DeBug "Base release is RHEL-8.3"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.3 *****" | tee -a $OUTPUTFILE
                    Release="8.3"
                    ;;
                305)
                    # RHEL-8.4
                    DeBug "Base release is RHEL-8.4"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.4 *****" | tee -a $OUTPUTFILE
                    Release="8.4"
                    if cki_kver_lt "4.18.0-305.8.1.el8_4"; then
                        sed -i "/pinctrl-emmitsburg\.ko/d"  ${OS}/${Release}/8.4-modules-${ARCH}.lst
                    fi
                    #known issue: bz1968381
                    if cki_kver_lt "4.18.0-305.11.1.el8_4"; then
                        sed -i "/dptf_power\.ko/d" ${OS}/${Release}/8.4-modules-${ARCH}.lst
                    fi
                    ;;
                348)
                    # RHEL-8.5
                    DeBug "Base release is RHEL-8.5"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.5 *****" | tee -a $OUTPUTFILE
                    Release="8.5"
                    ;;
                372)
                    # RHEL-8.6
                    DeBug "Base release is RHEL-8.6"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.6 *****" | tee -a $OUTPUTFILE
                    Release="8.6"
                    # known issue: bz2129923
                    if cki_kver_lt "4.18.0-372.32.1.el8_6"; then
                        sed -i "/hpilo\.ko/d"  ${OS}/${Release}/8.6-modules-aarch64.lst
                    fi
                    ;;
                425)
                    # RHEL-8.7
                    DeBug "Base release is RHEL-8.7"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.7 *****" | tee -a $OUTPUTFILE
                    Release="8.7"
                    ;;
                477)
                    # RHEL-8.8
                    DeBug "Base release is RHEL-8.8"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-8.8 *****" | tee -a $OUTPUTFILE
                    Release="8.8"
                    ;;
                *)
                    # We are currently developing RHEL-8.9
                    # Therefore we test at HEAD-RHEL-8.9
                    # Need to refresh the list after 8.9 GA
                    DeBug "Base release is HEAD-RHEL-8.9"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is HEAD-RHEL-8.8 *****" | tee -a $OUTPUTFILE
                    Release="HEAD-8.9"
                    ;;
            esac
        elif [ "${K_VER}" = "5.14.0" ]; then
            # This is RHEL9
            OS="RHEL9"
            case ${Base} in
                70)
                    # RHEL-9.0
                    DeBug "Base release is RHEL-9.0"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-9.0 *****" | tee -a $OUTPUTFILE
                    Release="9.0"
                    if cki_kver_lt "5.14.0-70.30.1.el9_0"; then
                        sed -i '/libarc4.ko/d' ${OS}/${Release}/$Release-knownRemoved-s390x.lst
                        sed -i '/cifs_arc4.ko/d;/cifs_md4.ko/d;' ${OS}/${Release}/$Release-modules-x86_64.lst
                    fi
                    ;;
                162)
                    # RHEL-9.1
                    DeBug "Base release is RHEL-9.1"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-9.1 *****" | tee -a $OUTPUTFILE
                    Release="9.1"
                    ;;
                284)
                    # RHEL-9.2
                    DeBug "Base release is RHEL-9.2"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is RHEL-9.2 *****" | tee -a $OUTPUTFILE
                    Release="9.2"
                    ;;
                *)
                    # Still in developing phase, need to update in future.
                    DeBug "Base release is HEAD-RHEL-9.3"
                    echo "" | tee -a $OUTPUTFILE
                    echo "***** $ARCH: Base release is HEAD-RHEL-9.3 *****" | tee -a $OUTPUTFILE
                    Release="HEAD-9.3"
                    if cki_kver_lt "5.14.0-288.el9"; then
                        sed -i '/pinctrl-meteorlake.ko/d' ${OS}/${Release}/$Release-modules-x86_64.lst
                    fi
                    if cki_kver_lt "5.14.0-292.el9"; then
                        sed -i '/cxl_acpi.ko/d; /cxl_core.ko/d; /cxl_port.ko/d' ${OS}/${Release}/$Release-modules-$ARCH.lst
                    fi
                    if cki_kver_lt "5.14.0-295.el9"; then
                        sed -i '/nd_blk.ko/d' ${OS}/${Release}/$Release-knownRemoved-$ARCH.lst
                    fi
                    if cki_kver_lt "5.14.0-297.el9"; then
                        sed -i '/vfio_spapr_eeh.ko/d; /vfio_virqfd.ko/d'  ${OS}/${Release}/$Release-knownRemoved-$ARCH.lst
                    fi
                    if cki_kver_lt "5.14.0-298.el9"; then
                        sed -i '/ssif_bmc.ko/d' ${OS}/${Release}/$Release-modules-aarch64.lst
                    fi
                    if cki_kver_lt "5.14.0-307.el9"; then
                        sed -i '/^cec.ko$/d; /drm_buddy.ko/d; /drm_display_helper.ko/d' ${OS}/${Release}/$Release-modules-s390x.lst
                    fi
                    if cki_kver_lt "5.14.0-310.el9"; then
                        sed -i '/^intel_ifs.ko$/d' ${OS}/${Release}/$Release-modules-x86_64.lst
                    fi
                    if cki_kver_lt "5.14.0-311.el9"; then
                        for module in $(cat ${OS}/${Release}/aarch64-modules-5.14.0-311.el9)
                        # File ${OS}/${Release}/aarch64-modules-5.14.0-311.el9 can be removed after 9.3 GA with code clean up
                        do
                            sed -i "/^${module}$/d" ${OS}/${Release}/$Release-modules-aarch64.lst
                        done
                    fi
                    if cki_kver_lt "5.14.0-314.el9"; then
                        sed -i '/^rdma_rxe.ko$/d' ${OS}/${Release}/$Release-modules-$ARCH.lst
                        sed -i '/^marvell_cn10k_ddr_pmu.ko$/d' ${OS}/${Release}/$Release-modules-aarch64.lst
                    fi
                    if cki_kver_lt "5.14.0-316.el9"; then
                        sed -i '/^sch_mqprio_lib.ko$/d' ${OS}/${Release}/$Release-modules-$ARCH.lst
                    fi
                    if cki_kver_lt "5.14.0-318.el9"; then
                        sed -i '/brcmfmac-bca.ko/d; /brcmfmac-cyw.ko/d; /brcmfmac-wcc.ko/d' ${OS}/${Release}/$Release-modules-{aarch64,x86_64}.lst
                    fi
                    if cki_kver_lt "5.14.0-323.el9"; then
                        sed -i '/^marvell_cn10k_tad_pmu.ko$/d' ${OS}/${Release}/$Release-modules-aarch64.lst
                    fi
                    if cki_kver_lt "5.14.0-324.el9"; then
                        sed -i '/^i3c.ko$/d; /svc-i3c-master.ko/d' ${OS}/${Release}/$Release-modules-aarch64.lst
                    fi
                    if cki_kver_lt "5.14.0-327.el9"; then
                        sed -i '/rtc-v3020.ko/d' ${OS}/${Release}/$Release-knownRemoved-$ARCH.lst
                        sed -i '/rtw89_8852be.ko/d; /rtw89_8852b.ko/d' ${OS}/${Release}/$Release-modules-{aarch64,x86_64}.lst
                    fi
                    ;;
            esac
        elif [ -n "$(echo ${K_NAME} | grep kernel-pegas)" -a "${K_VER}" = "4.10.0" ]; then
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
        fi

        # Lets determine the module list for the current kernel package
        DeBug "Call GetCurrentModuleList"
        GetCurrentModuleList
        DeBug "Return GetCurrentModuleList"

        # Lets determine the module list for the base release kernel package
        DeBug "Call GetBaseModuleList"
        GetBaseModuleList
        DeBug "Return GetBaseModuleList"

        # Lets determine the known removed module list for the base release kernel package
        DeBug "Call GetKnownRemovedList"
        GetKnownRemovedList
        DeBug "Return GetKnownRemovedList"

        # Lets submit the complete log from the diff of base module list and the current module list
        diff -u ${TESTAREA}/moduleList_base ${TESTAREA}/moduleList_current > ${TESTAREA}/moduleList_base-current_diff
        cp ${TESTAREA}/moduleList_base-current_diff ${TESTAREA}/moduleList_base-current_diff.log
        cki_upload_log_file ${TESTAREA}/moduleList_base-current_diff.log

        #
        # Compared: Lets compare the base and current module lists
        #
        echo "" | tee -a $OUTPUTFILE
        echo "***** $ARCH: Comparing base and current module lists. *****" | tee -a $OUTPUTFILE
        echo "***** Stored compare module list: ${TESTAREA}/moduleList_base-current_diff.log *****" | tee -a $OUTPUTFILE

        # Check new added modules
        diff -u ${TESTAREA}/moduleList_base ${TESTAREA}/moduleList_current | grep -e "^+" > ${TESTAREA}/moduleList_compare_added
        FileClean moduleList_compare_added

        echo "" | tee -a $OUTPUTFILE
        echo "***** $ARCH: Checking against "New added" modules list. *****" | tee -a $OUTPUTFILE

        if [ ! -s ${TESTAREA}/moduleList_compare_added ]; then
            echo "***** PASS: *****" | tee -a $OUTPUTFILE
            echo "***** Files checked. There are no new modules. *****" | tee -a $OUTPUTFILE
            rlPass "New added modules check PASS"
        else
            echo "***** WARNING: *****" | tee -a $OUTPUTFILE
            echo "***** Files compared. There are new modules!!! *****" | tee -a $OUTPUTFILE
            cp ${TESTAREA}/moduleList_compare_added ${TESTAREA}/moduleList_compare_added.log
            cki_upload_log_file ${TESTAREA}/moduleList_compare_added.log
            rlLogWarning "Existing new module(s), please update case!"
            echo "**************************************" | tee -a $OUTPUTFILE
            cat ${TESTAREA}/moduleList_compare_added | tee -a $OUTPUTFILE
            echo "**************************************" | tee -a $OUTPUTFILE
            rlPass "Warn: existing new added modules"
        fi

        diff -u ${TESTAREA}/moduleList_base ${TESTAREA}/moduleList_current | grep -e "^-" > ${TESTAREA}/moduleList_compare

        # Lets clean up the format of our diff outputfile
        FileClean moduleList_compare

        if [ ! -s "${TESTAREA}/moduleList_compare" ]; then
            # RHEL6 only: There is one final test for RHEL6
            if [ "${K_VER}" = "2.6.32" ]; then
                RHEL6_TestBZ839667
            fi

            # If we get here there are no missing modules
            echo "" | tee -a $OUTPUTFILE
            echo "***** PASS: *****" | tee -a $OUTPUTFILE
            echo "***** Files compared. There are no missing modules. *****" | tee -a $OUTPUTFILE
            DeBug "Files compared. There are no missing modules."
            cki_print_info "Compared"
        fi

        echo "***** Stored compare module list: ${TESTAREA}/moduleList_compare *****" | tee -a $OUTPUTFILE

        #
        # Checked: Lets check against the "known removed" list
        #
        echo "" | tee -a $OUTPUTFILE
        echo "***** $ARCH: Checking against "known removed" modules list. *****" | tee -a $OUTPUTFILE

        diff -u ${TESTAREA}/moduleList_compare ${TESTAREA}/moduleList_knownRemoved | grep -e "^-" > ${TESTAREA}/moduleList_missing

        # Lets clean up the format of our diff outputfile
        FileClean moduleList_missing

        if [ ! -s "${TESTAREA}/moduleList_missing" ]; then
            # RHEL6 only: There is one final test for RHEL6
            if [ "${K_VER}" = "2.6.32" ]; then
                RHEL6_TestBZ839667
            fi

            # If we get here there are no missing modules
            echo "" | tee -a $OUTPUTFILE
            echo "***** PASS: *****" | tee -a $OUTPUTFILE
            echo "***** Files checked. There are no missing modules. *****" | tee -a $OUTPUTFILE
            DeBug "Files checked. There are no missing modules."
            cki_print_info "Checked"
        else
            echo "***** Stored missing module list: ${TESTAREA}/moduleList_missing *****" | tee -a $OUTPUTFILE
            # This is a fail. There are missing modules.

            # We still need to do the final RHEL6 test
            # RHEL6 only: There is one final test for RHEL6
            if [ "${K_VER}" = "2.6.32" ]; then
                RHEL6_TestBZ839667
            fi

            DisplayModuleFail moduleList_missing
            cp ${TESTAREA}/moduleList_missing ${TESTAREA}/moduleList_missing.log
            cki_upload_log_file ${TESTAREA}/moduleList_missing.log
            DeBug "Files checked. There are missing modules."
            cki_print_info "Checked"
            rlFail "There are missing modules!"
        fi
    rlPhaseEnd
rlJournalEnd

rlJournalPrintText
# EndFile
