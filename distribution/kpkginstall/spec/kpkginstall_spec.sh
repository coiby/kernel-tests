#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include distribution/kpkginstall/runtest.sh

KERNEL_RPM_URL="https://example.com/715398316/x86_64/5.14.0-207.mr1748_715398316.el9.x86_64#package_name=kernel&amp;source_package_name=kernel"
KERNEL_RT_RPM_URL="https://example.com/715398316/x86_64/5.14.0-207.mr1748_715398316.el9.x86_64#package_name=kernel-rt&amp;source_package_name=kernel-rt"
KERNEL_DEBUG_PARAM_RPM_URL="https://example.com/job/12345/repo#package_name=kernel&amp;source_package_name=kernel&amp;debug_kernel=true"
KERNEL_DEBUG_PKG_RPM_URL="https://example.com/job/12345/x86_64/5.14.0-276.2037_789873082.el9.x86_64#package_name=kernel-debug&source_package_name=kernel"
KERNEL_64k_RPM_URL="https://example.com/job/12345/repo#package_name=kernel-64k&amp;source_package_name=kernel"
KERNEL_TGZ_URL="https://example.com/715092599/x86_64/artifacts/kernel-mainline.kernel.org-redhat_715092599_x86_64.tar.gz#package_name=kernel&amp;source_package_name=kernel"

Describe 'kpkginstall: parse_kpkg_url_variables'
    __end__() {
        # The "run source" is run in a subshell, so you need to use "%preserve"
        # to preserve variables
        %preserve KPKG_VAR_PACKAGE_NAME KPKG_VAR_DEBUG_KERNEL
    }
    Parameters
        "kernel" kernel "" rpms "$KERNEL_RPM_URL"
        "kernel-rt" kernel-rt "" rpms "$KERNEL_RT_RPM_URL"
        "kernel-debug" kernel true rpms "$KERNEL_DEBUG_PARAM_RPM_URL"
        "kernel-debug" kernel-debug "" rpms "$KERNEL_DEBUG_PKG_RPM_URL"
        "kernel-64k" kernel-64k "" rpms "$KERNEL_64k_RPM_URL"
        "kernel" kernel "" tarball "$KERNEL_TGZ_URL"
    End
    It "can parse $1 from $4"
        export KPKG_URL="$5"
        When call parse_kpkg_url_variables
        The first line should equal "✅ Found URL parameter: PACKAGE_NAME=$2"
        The variable KPKG_VAR_PACKAGE_NAME should equal "$2"
        if [ -n "$3" ]; then
            The variable KPKG_VAR_DEBUG_KERNEL should equal "$3"
        fi
        The status should be success
    End
End

Describe 'kpkginstall: set_package_name set package name'
    setup(){
        mkdir -p /var/tmp/kpkginstall
    }
    cleanup(){
        rm -rf /var/tmp/kpkginstall
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    Parameters
        kernel kernel kernel ""
        kernel-rt kernel-rt kernel-rt ""
        kernel-debug kernel kernel true
        kernel-debug kernel-debug kernel ""
        kernel-rt-debug kernel-rt kernel-rt true
        kernel-64k kernel-64k kernel ""
    End
    It "can set $1 as package name"
        export EXPECTED_PACKAGE_NAME=$1         # package_name + debug (in case of debug kernels)
        export KPKG_VAR_PACKAGE_NAME=$2
        export KPKG_VAR_SOURCE_PACKAGE_NAME=$3
        export KPKG_VAR_DEBUG_KERNEL=$4
        When call set_package_name
        The first line should equal "✅ Found package name in URL variables: $KPKG_VAR_PACKAGE_NAME"
        if [ -z "$KPKG_VAR_DEBUG_KERNEL" ]; then
            The line 3 should equal "✅ Package name is set: $EXPECTED_PACKAGE_NAME (cached to disk)"
            The line 4 should equal "✅ Source package name is set: $KPKG_VAR_SOURCE_PACKAGE_NAME (cached to disk)"
        else
            The line 3 should equal "ℹ️ Debug kernel was requested -- appending -debug to package name"
            The line 4 should equal "✅ Package name is set: $EXPECTED_PACKAGE_NAME (cached to disk)"
            The line 5 should equal "✅ Source package name is set: $KPKG_VAR_SOURCE_PACKAGE_NAME (cached to disk)"
        fi
        The contents of file /var/tmp/kpkginstall/KPKG_PACKAGE_NAME should equal "$EXPECTED_PACKAGE_NAME"
        The contents of file /var/tmp/kpkginstall/KPKG_SOURCE_PACKAGE_NAME should equal "$SOURCE_PACKAGE_NAME"
    End
End

Describe 'kpkginstall: set_package_name read package name'
    setup(){
        mkdir -p /var/tmp/kpkginstall
        echo "kernel" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
    }
    cleanup(){
        rm -rf /var/tmp/kpkginstall
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    It 'set_package_name works after reboot'
        # Call for the second time as it is done after reboot
        export REBOOTCOUNT=1
        When call set_package_name
        The first line should equal "✅ Found cached package name on disk: kernel"
        The status should be success
    End
End

Describe 'kpkginstall: rpm_prepare'
    Parameters
        kernel "$KERNEL_RPM_URL"
        kernel-debug "$KERNEL_RPM_URL"
        kernel-rt "$KERNEL_RPM_URL"
        kernel-64k "$KERNEL_64k_RPM_URL"
    End
    It "can prepare cki repo for package $1"
        export PACKAGE_NAME=$1
        export KPKG_URL=$2
        select_yum_tool(){
            echo ""
        }
        excluded_pkgs="error: unset"
        if [[ "${PACKAGE_NAME}" == "kernel" ]]; then
            excluded_pkgs=(kernel-debug kernel-debug-core
                           kernel-rt kernel-rt-core \
                           kernel-rt-debug kernel-rt-debug-core \
                           kernel-automotive kernel-automotive-debug \
                           kernel-64k kernel-64k-debug)
        fi
        if [[ "${PACKAGE_NAME}" == "kernel-debug" ]]; then
            excluded_pkgs=(kernel kernel-core \
                           kernel-rt kernel-rt-core \
                           kernel-rt-debug kernel-rt-debug-core
                           kernel-automotive kernel-automotive-debug \
                           kernel-64k kernel-64k-debug)
        fi
        if [[ "${PACKAGE_NAME}" == "kernel-rt" ]]; then
            excluded_pkgs=(kernel kernel-core \
                           kernel-debug kernel-debug-core \
                           kernel-rt-debug kernel-rt-debug-core
                           kernel-automotive kernel-automotive-debug \
                           kernel-64k kernel-64k-debug)
        fi
        if [[ "${PACKAGE_NAME}" == "kernel-64k" ]]; then
            excluded_pkgs=(kernel kernel-core \
                           kernel-debug kernel-debug-core \
                           kernel-rt kernel-rt-core \
                           kernel-rt-debug kernel-rt-debug-core
                           kernel-automotive kernel-automotive-debug)
        fi
        When call rpm_prepare
        The line 2 should equal "✅ Kernel repository file deployed"
        The contents of file /etc/yum.repos.d/kernel-cki.repo should include "exclude=${excluded_pkgs[*]}"
    End
End

Describe 'kpkginstall: get_kpkg_ver rpms'
    cleanup(){
        rm -rf /var/tmp/kpkginstall
    }
    BeforeAll 'cleanup'
    AfterAll 'cleanup'
    It 'can set kernel version'
        export KPKG_URL="$KERNEL_RPM_URL"
        export YUM="dnf"
        export ARCH="ppc64le"
        dnf(){
            echo "kernel.ppc64le      4.18.0-442.el8        kernel-cki"
        }
        __end__() {
            # The "run source" is run in a subshell, so you need to use "%preserve"
            # to preserve variables
            %preserve REPO_NAME YUM
        }
        mkdir -p /var/tmp/kpkginstall
        When call get_kpkg_ver
        The variable REPO_NAME should eq "kernel-cki"
        The contents of file /var/tmp/kpkginstall/KPKG_KVER should equal "4.18.0-442.el8.ppc64le"
        The first line should equal "ℹ️ Repo Name set REPO_NAME=kernel-cki"
    End
    It 'can read kernel version after it was set the first time'
        # Call for the second time as it is done after reboot
        When call get_kpkg_ver
        The first line should equal "✅ Found kernel version string in cache on disk: 4.18.0-442.el8.ppc64le"
        The status should be success
    End
End

Describe 'kpkginstall: get_kpkg_ver tarball'
    cleanup(){
        rm -rf /var/tmp/kpkginstall
    }
    BeforeAll 'cleanup'
    AfterAll 'cleanup'
    It 'can set kernel version'
        export KPKG_URL="$KERNEL_TGZ_URL"
        tar(){
            echo "boot/vmlinuz-6.1.0-rc7"
        }
        mkdir -p /var/tmp/kpkginstall
        When call get_kpkg_ver
        The contents of file /var/tmp/kpkginstall/KPKG_KVER should equal "6.1.0-rc7"
    End
    It 'can read kernel version after it was set the first time'
        # Call for the second time as it is done after reboot
        When call get_kpkg_ver
        The first line should equal "✅ Found kernel version string in cache on disk: 6.1.0-rc7"
        The status should be success
    End
End

Describe 'kpkginstall: rpm_install'
    Parameters
        kernel kernel "s390x" "4.18.0-442.el8.s390x" "" "$KERNEL_RPM_URL"
        kernel-debug kernel "s390x" "4.18.0-442.el8.s390x" true "$KERNEL_RPM_URL"
        kernel-debug kernel-debug "s390x" "5.14.0-276.el9.s390x" "true" "$KERNEL_RPM_URL"
        kernel-rt kernel-rt "s390x" "4.18.0-442.el8.s390x" "" "$KERNEL_RPM_URL"
        kernel-64k kernel-64k "aarch64" "5.14.0-243.1820_756592390.el9.aarch64" "" "$KERNEL_64k_RPM_URL"
    End
    setup(){
        mkdir -p /var/tmp/kpkginstall
    }
    cleanup(){
        rm -rf /var/tmp/kpkginstall
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    It "can install $1"
        export PACKAGE_NAME="$2"
        export IS_DEBUG_KERNEL="$5"
        export KPKG_URL="$6"
        export YUM=dnf
        export ARCH="$3"
        export KVER_RPM="$4"
        export KVER_UNAME="$KVER_RPM"
        if [ "$PACKAGE_NAME" == "kernel-64k" ]; then
            KVER_UNAME="${KVER_UNAME}+64k"
        fi
        echo  "$KVER_RPM" > /var/tmp/kpkginstall/KPKG_KVER
        dnf(){
            return 0
        }
        grubby(){
            echo "grubby $*"
        }
        zipl(){
            echo "zipl"
        }
        When call rpm_install
        The first line should equal "ℹ️ rpm_install: Extracting kernel version from $KPKG_URL"
        The third line should equal "✅ Kernel version is $KVER_RPM"
        The stdout should include "✅ Downloaded ${PACKAGE_NAME}-$KVER_RPM successfully"
        The stdout should include "✅ Installed ${PACKAGE_NAME}-$KVER_RPM successfully"
        if [ "$PACKAGE_NAME" == "kernel-rt" ]; then
            The stdout should include "✅ Installed /usr/sbin/kernel-is-rt successfully"
        fi
        # message that is added on debug kernels
        if [ -n "$IS_DEBUG_KERNEL" ]; then
            The stdout should include "✅ Updated /etc/sysconfig/kernel to set debug kernels as default"
            The contents of file /etc/sysconfig/kernel should include "UPDATEDEFAULT=yes"
            The contents of file /etc/sysconfig/kernel should include "DEFAULTKERNEL=kernel-debug"
            The contents of file /etc/sysconfig/kernel should include "DEFAULTDEBUG=yes"
        fi
        The stdout should include "grubby --set-default /boot/vmlinuz-$KVER_UNAME"
        if [ "$ARCH" == "s390x" ]; then
            The stdout should include "zipl"
            The stdout should include "✅ Grubby workaround for s390x completed"
        fi
        The status should be success
    End
End

Describe 'kpkginstall: main - install kernel'
    Parameters
        kernel "$KERNEL_RPM_URL"
        kernel "$KERNEL_TGZ_URL"
        kernel-rt "$KERNEL_RT_RPM_URL"
        kernel-64k "$KERNEL_64k_RPM_URL"
        kernel "$KERNEL_DEBUG_PARAM_RPM_URL"
        kernel "$KERNEL_DEBUG_PKG_RPM_URL"
    End
    cleanup(){
        rm -rf /var/tmp/kpkginstall
    }
    AfterEach 'cleanup'
    It "can install with KPKG_URL=$2"
        export REBOOTCOUNT=0
        export KPKG_URL="$2"
        export YUM=dnf
        select_yum_tool() {
            return 0
        }
        dnf(){
            echo "dnf $*"
        }
        targz_install(){
            return 0
        }
        rpm_prepare(){
            return 0
        }
        rpm_install(){
            return 0
        }
        io_test(){
            return 10
        }
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 0"
        The stdout should include "✅ Found URL parameter: PACKAGE_NAME=$1"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/kernel-in-place PASS 0"
        The stdout should include "rstrnt-reboot"
        The status should be success
    End
End

uname(){
    if [ "$1" == "-r" ];then
        echo "$KERNEL_VERSION"
    fi
    if [ "$1" == "-i" ];then
        echo "${ARCH}"
    fi
}
select_yum_tool() {
    echo "select_yum_tool"
    return 0
}
get_kpkg_ver() {
    return 0
}
cat(){
    echo "cat $*"
}
io_test(){
    return 10
}
sysctl(){
    echo "sysctl $*"
}
dmesg(){
    echo "${MOCKED_DMESG:-}"
}
journalctl(){
    echo "${MOCKED_JOURNALCTL:-}"
}
which(){
    return 0
}
Describe 'kpkginstall: main - check installed kernel'
    Parameters
        # package name - arch - rpm package name rpm dnf repo query - uname -r - kernel url
        kernel "x86_64" "4.18.0-442.el8.x86_64" "4.18.0-442.el8.x86_64" "$KERNEL_RPM_URL"
        kernel "x86_64" "6.1.0-rc7" "6.1.0-rc7" "$KERNEL_TGZ_URL"
        kernel-rt "x86_64" "4.18.0-442.el8.x86_64" "4.18.0-442.el8.x86_64" "$KERNEL_RT_RPM_URL"
        kernel-64k "aarch64" "5.14.0-243.1820_756592390.el9.aarch64" "5.14.0-243.1820_756592390.el9.aarch64+64k" "$KERNEL_64k_RPM_URL"
        kernel-debug "s390x" "4.18.0-442.el8.s390x" "4.18.0-442.el8.s390x" "$KERNEL_DEBUG_PARAM_RPM_URL"
        kernel-debug "s390x" "4.18.0-442.el8.s390x" "4.18.0-442.el8.s390x" "$KERNEL_DEBUG_PKG_RPM_URL"
    End
    setup(){
        mkdir -p /var/tmp/kpkginstall
    }
    cleanup(){
        rm -rf /var/tmp/kpkginstall
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    export REBOOTCOUNT=1

    It "installed with KPKG_URL=$5"
        ARCH="$2"
        KVER="$3"
        #KVER is updated with in the main function
        KERNEL_VERSION="$4"
        echo "$1" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
        # skip the workaround from cross-compiling
        mkdir -p /usr/src/kernels/"$KERNEL_VERSION"/scripts/basic/
        touch /usr/src/kernels/"$KERNEL_VERSION"/scripts/basic/fixdep
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "Running kernel version string:     ${4}"
        The stdout should include "✅ Found the correct kernel version running!"
        The stdout should include "sysctl kernel.panic_on_oops"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/dmesg-check PASS 0"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/reboot PASS"
        The status should be success
    End

    It "can detect Call Traces on dmesg with KPKG_URL=$3"
        KVER="$2"
        #KVER is updated with in the main function
        KERNEL_VERSION="$2"
        echo "$1" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
        # skip the workaround from cross-compiling
        mkdir -p /usr/src/kernels/"$KVER"/scripts/basic/
        touch /usr/src/kernels/"$KVER"/scripts/basic/fixdep
        export MOCKED_DMESG="Call Trace:"
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel version running!"
        The stdout should include "sysctl kernel.panic_on_oops"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/dmesg-check WARN 7"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/reboot FAIL"
        The status should be success
    End

    It "can detect Call Traces on journalctl with KPKG_URL=$3"
        KVER="$2"
        #KVER is updated with in the main function
        KERNEL_VERSION="$2"
        echo "$1" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
        # skip the workaround from cross-compiling
        mkdir -p /usr/src/kernels/"$KVER"/scripts/basic/
        touch /usr/src/kernels/"$KVER"/scripts/basic/fixdep
        export MOCKED_JOURNALCTL="Call Trace:"
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel version running!"
        The stdout should include "sysctl kernel.panic_on_oops"
        The stdout should include "rstrnt-report-result distribution/kpkginstalljournalctl-check WARN 7"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/reboot FAIL"
        The status should be success
    End
End

Describe 'kpkginstall: main - check installed kernel with cross compiling'
    setup(){
        mkdir -p /var/tmp/kpkginstall
    }
    cleanup(){
        rm -rf /var/tmp/kpkginstall
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        rm -f  /usr/src/kernels/"$KVER"/.config
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    Parameters
        kernel "6.1.0-rc7" "$KERNEL_TGZ_URL"
    End
    export REBOOTCOUNT=1
    export ARCH="s390x"
    # For the workaround from cross-compiling
    Mock make
        echo "make $*"
        if grep -q "olddefconfig" <<< "$*"; then
            exit "${OLDERCONFIG_EXIT_CODE:=0}"
        fi
        if grep -q "modules_prepare" <<< "$*"; then
            exit "${MODULES_PREPARE_EXIT_CODE:=0}"
        fi
        if grep -q "scripts" <<< "$*"; then
            exit "${SCRIPTS_EXIT_CODE:=0}"
        fi
    End
    # The original cki_abort_recipe has exit 1 and shellspec doesn't like it
    # and aborts the run
    cki_abort_recipe(){
        echo "cki_abort_recipe $*"
        return 1
    }
    It "installed with KPKG_URL=$3 with cross compiling"
        KVER="$2"
        #KVER is updated with in the main function
        KERNEL_VERSION="$2"
        echo "$1" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
        # Make sure it will execute cross compiling path
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        # Create a dummy config to pass compiler/linker detection
        {
            echo "CONFIG_CC_IS_GCC=y"
            echo "CONFIG_LD_IS_BFD=y"
        } >/usr/src/kernels/"$KVER"/.config
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel version running!"
        The stdout should include "ℹ️ Workaround for cross compiling non x86_64 kernels"
        The stdout should include "sysctl kernel.panic_on_oops"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/dmesg-check PASS 0"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/reboot PASS"
        The status should be success
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    End

    It "installed with KPKG_URL=$3 with cross compiling fails on olddefconfig"
        KVER="$2"
        #KVER is updated with in the main function
        KERNEL_VERSION="$2"
        export OLDERCONFIG_EXIT_CODE=1
        echo "$1" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
        # Make sure it will execute cross compiling path
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        # Create a dummy config to pass compiler/linker detection
        {
            echo "CONFIG_CC_IS_GCC=y"
            echo "CONFIG_LD_IS_BFD=y"
        } >/usr/src/kernels/"$KVER"/.config
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel version running!"
        The stdout should include "ℹ️ Workaround for cross compiling non x86_64 kernels"
        The stdout should not include "make -C /usr/src/kernels/$KERNEL_VERSION modules_prepare"
        The stdout should include "cki_abort_recipe Failed applying cross compiling workaround WARN"
        The status should be success
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    End

    It "installed with KPKG_URL=$3 with cross compiling fails on modules_prepare"
        KVER="$2"
        #KVER is updated with in the main function
        KERNEL_VERSION="$2"
        export MODULES_PREPARE_EXIT_CODE=1
        echo "$1" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
        # Make sure it will execute cross compiling path
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        # Create a dummy config to pass compiler/linker detection
        {
            echo "CONFIG_CC_IS_GCC=y"
            echo "CONFIG_LD_IS_BFD=y"
        } >/usr/src/kernels/"$KVER"/.config
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel version running!"
        The stdout should include "ℹ️ Workaround for cross compiling non x86_64 kernels"
        The stdout should not include "make -C /usr/src/kernels/$KERNEL_VERSION scripts"
        The stdout should include "cki_abort_recipe Failed applying cross compiling workaround WARN"
        The status should be success
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    End

    It "installed with KPKG_URL=$3 with cross compiling fails on scripts"
        KVER="$2"
        #KVER is updated with in the main function
        KERNEL_VERSION="$2"
        export SCRIPTS_EXIT_CODE=1
        echo "$1" > /var/tmp/kpkginstall/KPKG_PACKAGE_NAME
        # Make sure it will execute cross compiling path
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        # Create a dummy config to pass compiler/linker detection
        {
            echo "CONFIG_CC_IS_GCC=y"
            echo "CONFIG_LD_IS_BFD=y"
        } >/usr/src/kernels/"$KVER"/.config
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel version running!"
        The stdout should include "ℹ️ Workaround for cross compiling non x86_64 kernels"
        The stdout should include "cki_abort_recipe Failed applying cross compiling workaround WARN"
        The status should be success
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    End
End
