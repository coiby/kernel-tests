#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include distribution/kpkginstall/runtest.sh

# kernel source package with variants
KERNEL_RPM_URL="https://example.com/715398316/x86_64/5.14.0-207.mr1748_715398316.el9.x86_64#package_name=kernel&amp;source_package_name=kernel"
KERNEL_64k_RPM_URL="https://example.com/job/12345/repo#package_name=kernel-64k&amp;source_package_name=kernel"
KERNEL_DEBUG_RPM_URL="https://example.com/job/12345/x86_64/5.14.0-276.2037_789873082.el9.x86_64#package_name=kernel-debug&source_package_name=kernel"
KERNEL_RT_RPM_URL="https://example.com/job/12345/x86_64/5.14.0-276.2037_789873082.el9.x86_64#package_name=kernel-rt&source_package_name=kernel"
# realtime branch
KERNEL_REALTIME_RPM_URL="https://example.com/715398316/x86_64/5.14.0-207.mr1748_715398316.el9.x86_64#package_name=kernel-rt&amp;source_package_name=kernel-rt"
# debug jobs
KERNEL_DEBUG_PARAM_RPM_URL="https://example.com/job/12345/repo#package_name=kernel&amp;source_package_name=kernel&amp;debug_kernel=true"
KERNEL_RT_DEBUG_PARAM_RPM_URL="https://example.com/job/12345/repo#package_name=kernel-rt&amp;source_package_name=kernel&amp;debug_kernel=true"
# realtime branch debug jobs
KERNEL_REALTIME_DEBUG_PARAM_RPM_URL="https://example.com/715398316/x86_64/5.14.0-207.mr1748_715398316.el9.x86_64#package_name=kernel-rt&amp;source_package_name=kernel-rt&amp;debug_kernel=true"
# tarballs
KERNEL_TGZ_URL="https://example.com/715092599/x86_64/artifacts/kernel-mainline.kernel.org-redhat_715092599_x86_64.tar.gz#package_name=kernel&amp;source_package_name=kernel"

Describe 'kpkginstall: parse_kpkg_url_variables'
    __end__() {
        # The "run source" is run in a subshell, so you need to use "%preserve"
        # to preserve variables
        %preserve KPKG_VAR_SOURCE_PACKAGE_NAME KPKG_VAR_PACKAGE_NAME KPKG_VAR_DEBUG_KERNEL
    }
    Parameters
        # KPKG_URL                                     KPKG_SOURCE_PACKAGE_NAME KPKG_PACKAGE_NAME KPKG_VAR_DEBUG_KERNEL
        # kernel source package with variants
        "${KERNEL_RPM_URL}"                            kernel                   kernel            ""
        "${KERNEL_64k_RPM_URL}"                        kernel                   kernel-64k        ""
        "${KERNEL_DEBUG_RPM_URL}"                      kernel                   kernel-debug      ""
        "${KERNEL_RT_RPM_URL}"                         kernel                   kernel-rt         ""
        # realtime branch
        "${KERNEL_REALTIME_RPM_URL}"                   kernel-rt                kernel-rt         ""
        # debug jobs
        "${KERNEL_DEBUG_PARAM_RPM_URL}"                kernel                   kernel            true
        "${KERNEL_RT_DEBUG_PARAM_RPM_URL}"             kernel                   kernel-rt         true
        # realtime branch debug jobs
        "${KERNEL_REALTIME_DEBUG_PARAM_RPM_URL}"       kernel-rt                kernel-rt         true
        # tarballs
        "${KERNEL_TGZ_URL}"                            kernel                   kernel            ""
    End
    It "can parse $1"
        export KPKG_URL=$1
        export EXPECTED_KPKG_VAR_SOURCE_PACKAGE_NAME=$2
        export EXPECTED_KPKG_VAR_PACKAGE_NAME=$3
        export EXPECTED_KPKG_VAR_DEBUG_KERNEL=$4
        When call parse_kpkg_url_variables
        The second line should equal "✅ Found URL parameter: SOURCE_PACKAGE_NAME=${EXPECTED_KPKG_VAR_SOURCE_PACKAGE_NAME}"
        The variable KPKG_VAR_SOURCE_PACKAGE_NAME should equal "${EXPECTED_KPKG_VAR_SOURCE_PACKAGE_NAME}"
        The first line should equal "✅ Found URL parameter: PACKAGE_NAME=${EXPECTED_KPKG_VAR_PACKAGE_NAME}"
        The variable KPKG_VAR_PACKAGE_NAME should equal "${EXPECTED_KPKG_VAR_PACKAGE_NAME}"
        if [[ -n ${EXPECTED_KPKG_VAR_DEBUG_KERNEL} ]]; then
            The variable KPKG_VAR_DEBUG_KERNEL should equal "${EXPECTED_KPKG_VAR_DEBUG_KERNEL}"
        fi
        The status should be success
    End
End


Describe 'kpkginstall: clean_kpkg_url_variables'
    Parameters
        # KPKG_SOURCE_PACKAGE_NAME KPKG_PACKAGE_NAME KPKG_VAR_DEBUG_KERNEL EXPECTED_KPKG_VAR_SOURCE_PACKAGE_NAME EXPECTED_KPKG_VAR_PACKAGE_NAME EXPECTED_KPKG_VAR_VARIANT_SUFFIX
        # kernel source package with variants
        kernel                     kernel            ""                    kernel                                kernel                         ""
        kernel                     kernel-64k        ""                    kernel                                kernel-64k                     -64k
        kernel                     kernel-debug      ""                    kernel                                kernel-debug                   -debug
        kernel                     kernel-rt         ""                    kernel                                kernel-rt                      -rt
        # realtime branch
        kernel-rt                  kernel-rt         ""                    kernel-rt                             kernel-rt                      ""
        # debug jobs
        kernel                     kernel            true                  kernel                                kernel-debug                   -debug
        kernel                     kernel-rt         true                  kernel                                kernel-rt-debug                -rt-debug
        # realtime branch debug jobs
        kernel-rt                  kernel-rt         true                  kernel-rt                             kernel-rt-debug                -debug
    End
    It "can clean $1/$2/$3"
        export KPKG_VAR_SOURCE_PACKAGE_NAME=$1
        export KPKG_VAR_PACKAGE_NAME=$2
        export KPKG_VAR_DEBUG_KERNEL=$3
        export EXPECTED_KPKG_VAR_SOURCE_PACKAGE_NAME=$4
        export EXPECTED_KPKG_VAR_PACKAGE_NAME=$5
        export EXPECTED_KPKG_VAR_VARIANT_SUFFIX=$6
        When call clean_kpkg_url_variables
        The variable KPKG_VAR_SOURCE_PACKAGE_NAME should equal "${EXPECTED_KPKG_VAR_SOURCE_PACKAGE_NAME}"
        The variable KPKG_VAR_PACKAGE_NAME should equal "${EXPECTED_KPKG_VAR_PACKAGE_NAME}"
        The variable KPKG_VAR_VARIANT_SUFFIX should equal "${EXPECTED_KPKG_VAR_VARIANT_SUFFIX}"
        The variable KPKG_VAR_DEBUG_KERNEL should be undefined
        The status should be success
    End
End

Describe 'kpkginstall: store_kpkg_url_variables'
    setup() {
        mkdir -p /var/tmp/kpkginstall/vars
    }
    cleanup() {
        rm -rf /var/tmp/kpkginstall/vars
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    It "can store KPKG_VAR_* variables"
        export KPKG_VAR_FOO=foo
        export KPKG_VAR_BAR=bar
        export KPKG_BAZ=baz
        When call store_kpkg_url_variables
        The contents of file /var/tmp/kpkginstall/vars/KPKG_VAR_FOO should equal "${KPKG_VAR_FOO}"
        The contents of file /var/tmp/kpkginstall/vars/KPKG_VAR_BAR should equal "${KPKG_VAR_BAR}"
        The file /var/tmp/kpkginstall/vars/KPKG_BAZ should not be exist
        The status should be success
    End
End

Describe 'kpkginstall: load_kpkg_url_variables'
    setup() {
        mkdir -p /var/tmp/kpkginstall/vars
    }
    cleanup() {
        rm -rf /var/tmp/kpkginstall/vars
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    It "can load KPKG_VAR_* variables"
        echo -n "foo" > /var/tmp/kpkginstall/vars/KPKG_VAR_FOO
        echo -n "bar" > /var/tmp/kpkginstall/vars/KPKG_VAR_BAR
        When call load_kpkg_url_variables
        The variable KPKG_VAR_FOO should equal "foo"
        The variable KPKG_VAR_BAR should equal "bar"
        The status should be success
    End

    It "copes with an empty vars directory"
        When call load_kpkg_url_variables
        The status should be success
    End
End

Describe 'kpkginstall: print_kpkg_url_variables_rpm'
    Parameters
        # SOURCE_PACKAGE_NAME PACKAGE_NAME VARIANT_SUFFIX
        # kernel source package with variants
        kernel                     kernel            ""
        kernel                     kernel-64k        -64k
        kernel                     kernel-debug      -debug
        kernel                     kernel-rt         -rt
        # realtime branch
        kernel-rt                  kernel-rt         ""
        # debug jobs
        kernel                     kernel            -debug
        kernel                     kernel-rt         -rt-debug
        # realtime branch debug jobs
        kernel-rt                  kernel-rt         -debug
    End
    It "can print $1/$2/$3"
        export KPKG_VAR_SOURCE_PACKAGE_NAME=$1
        export KPKG_VAR_PACKAGE_NAME=$2
        export KPKG_VAR_VARIANT_SUFFIX=$3
        When call print_kpkg_url_variables_rpm
        The line 1 should equal "✅ Source package name: ${KPKG_VAR_SOURCE_PACKAGE_NAME}"
        The line 2 should equal "✅ Package name: ${KPKG_VAR_PACKAGE_NAME}"
        The line 3 should equal "✅ Variant suffix: ${KPKG_VAR_VARIANT_SUFFIX}"
    End
End

Describe 'kpkginstall: kpkg_release'
    Parameters
        # KVER             VARIANT_SUFFIX  URL                          EXPECTED_RELEASE
        5.14.0.el9.x86_64  ""              https://some-url             5.14.0.el9.x86_64
        5.14.0.el6.x86_64  -rt-debug       https://some-url             5.14.0.el6.x86_64.rt-debug
        5.14.0.el7.x86_64  -rt-debug       https://some-url             5.14.0.el7.x86_64.rt-debug
        5.14.0.el8.x86_64  -rt-debug       https://some-url             5.14.0.el8.x86_64+rt-debug
        5.14.0.el9.x86_64  -rt-debug       https://some-url             5.14.0.el9.x86_64+rt-debug
        5.14.0.x86_64      ""              https://some-url/foo.tar.gz  5.14.0
    End

    It "can determine the release for $1/$2"
        export KVER=$1
        export KPKG_VAR_VARIANT_SUFFIX=$2
        export KPKG_URL=$3
        export EXPECTED_KPKG_RELEASE=$4
        When call kpkg_release
        The stdout should equal "${EXPECTED_KPKG_RELEASE}"
    End
End

Describe 'kpkginstall: rpm_prepare'
    Parameters
        kernel
        kernel-debug
        kernel-64k
        kernel-64k-debug
        kernel-rt
        kernel-rt-debug
        kernel-automotive
    End
    It "can prepare cki repo for package $1"
        export KPKG_VAR_PACKAGE_NAME=$1
        export KPKG_URL=https://some-url
        select_yum_tool() {
            echo ""
        }
        excluded_pkgs="error: unset"
        case "${KPKG_VAR_PACKAGE_NAME}" in
            kernel)
                excluded_pkgs=(
                    kernel-debug kernel-debug-core
                    kernel-64k kernel-64k-core
                    kernel-64k-debug kernel-64k-debug-core
                    kernel-rt kernel-rt-core
                    kernel-rt-debug kernel-rt-debug-core
                    kernel-automotive kernel-automotive-core
                    kernel-automotive-debug kernel-automotive-debug-core
                )
                ;;
            kernel-debug)
                excluded_pkgs=(
                    kernel kernel-core
                    kernel-64k kernel-64k-core
                    kernel-64k-debug kernel-64k-debug-core
                    kernel-rt kernel-rt-core
                    kernel-rt-debug kernel-rt-debug-core
                    kernel-automotive kernel-automotive-core
                    kernel-automotive-debug kernel-automotive-debug-core
                )
                ;;
            kernel-64k)
                excluded_pkgs=(
                    kernel kernel-core
                    kernel-debug kernel-debug-core
                    kernel-64k-debug kernel-64k-debug-core
                    kernel-rt kernel-rt-core
                    kernel-rt-debug kernel-rt-debug-core
                    kernel-automotive kernel-automotive-core
                    kernel-automotive-debug kernel-automotive-debug-core
                )
                ;;
            kernel-64k-debug)
                excluded_pkgs=(
                    kernel kernel-core
                    kernel-debug kernel-debug-core
                    kernel-64k kernel-64k-core
                    kernel-rt kernel-rt-core
                    kernel-rt-debug kernel-rt-debug-core
                    kernel-automotive kernel-automotive-core
                    kernel-automotive-debug kernel-automotive-debug-core
                )
                ;;
            kernel-rt)
                excluded_pkgs=(
                    kernel kernel-core
                    kernel-debug kernel-debug-core
                    kernel-64k kernel-64k-core
                    kernel-64k-debug kernel-64k-debug-core
                    kernel-rt-debug kernel-rt-debug-core
                    kernel-automotive kernel-automotive-core
                )
                ;;
            kernel-rt-debug)
                excluded_pkgs=(
                    kernel kernel-core
                    kernel-debug kernel-debug-core
                    kernel-64k kernel-64k-core
                    kernel-64k-debug kernel-64k-debug-core
                    kernel-rt kernel-rt-core
                    kernel-automotive kernel-automotive-core
                )
                ;;
            kernel-automotive)
                excluded_pkgs=(
                    kernel kernel-core
                    kernel-debug kernel-debug-core
                    kernel-64k kernel-64k-core
                    kernel-64k-debug kernel-64k-debug-core
                    kernel-rt kernel-rt-core
                    kernel-rt-debug kernel-rt-debug-core
                    kernel-automotive-debug kernel-automotive-debug-core
                )
                ;;
            *)
                false
                ;;
        esac
        When call rpm_prepare
        The line 2 should equal "✅ Kernel repository file deployed"
        for excluded_pkg in "${excluded_pkgs[@]}"; do
            The line 6 of contents of file /etc/yum.repos.d/kernel-cki.repo \
                should match pattern "exclude=* ${excluded_pkg} *|exclude=${excluded_pkg} *|exclude=* ${excluded_pkg}"
        done
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
        mkdir -p /var/tmp/kpkginstall/vars
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
        mkdir -p /var/tmp/kpkginstall/vars
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
        # SOURCE_PACKAGE_NAME    PACKAGE_NAME      VARIANT_SUFFIX ARCH     KVER_RPM                                 EXPECTED_KVER_UNAME
        # kernel source package with variants
        kernel                   kernel            ""             s390x    "4.18.0-442.el8.s390x"                   "4.18.0-442.el8.s390x"
        kernel                   kernel-64k        -64k           aarch64  "5.14.0-243.1820_756592390.el9.aarch64"  "5.14.0-243.1820_756592390.el9.aarch64+64k"
        kernel                   kernel-debug      -debug         s390x    "5.14.0-276.el9.s390x"                   "5.14.0-276.el9.s390x+debug"
        kernel                   kernel-rt         -rt            s390x    "5.14.0-276.el9.s390x"                   "5.14.0-276.el9.s390x+rt"
        # realtime branch
        kernel-rt                kernel-rt         ""             s390x    "4.18.0-442.el8.s390x"                   "4.18.0-442.el8.s390x"
        # debug jobs
        kernel                   kernel-rt-debug   -rt-debug      s390x    "5.14.0-276.el9.s390x"                   "5.14.0-276.el9.s390x+rt-debug"
        # realtime branch debug jobs
        kernel-rt                kernel-rt-debug   -debug         s390x    "5.14.0-276.el9.s390x"                   "5.14.0-276.el9.s390x+debug"
    End
    setup() {
        mkdir -p /var/tmp/kpkginstall/vars
    }
    cleanup() {
        rm -rf /var/tmp/kpkginstall
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    dnf() {
        return 0
    }
    grubby() {
        echo "grubby $*"
    }
    zipl() {
        echo "zipl"
    }
    depmod() {
        if [[ -n "$MOCKED_DEPMOD" ]]; then
            echo "${MOCKED_DEPMOD}"
        fi
    }
    It "can install $1/$2/$3/$4"
        export KPKG_VAR_SOURCE_PACKAGE_NAME=$1
        export KPKG_VAR_PACKAGE_NAME=$2
        export KPKG_VAR_VARIANT_SUFFIX=$3
        export ARCH=$4
        export KVER_RPM=$5
        export EXPECTED_KVER_UNAME=$6
        export YUM=dnf
        export KPKG_URL=https://some-url
        echo "${KVER_RPM}" > /var/tmp/kpkginstall/KPKG_KVER
        When call rpm_install
        The first line should equal "ℹ️ rpm_install: Extracting kernel version from ${KPKG_URL}"
        The third line should equal "✅ Kernel version is ${KVER_RPM}"
        The stdout should include "✅ Downloaded ${KPKG_VAR_PACKAGE_NAME}-${KVER_RPM} successfully"
        The stdout should include "✅ Installed ${KPKG_VAR_PACKAGE_NAME}-${KVER_RPM} successfully"
        if [[ ${KPKG_VAR_PACKAGE_NAME} == kernel-rt* ]]; then
            The stdout should include "✅ Installed /usr/sbin/kernel-is-rt successfully"
        fi
        The stdout should include "grubby --set-default /boot/vmlinuz-${EXPECTED_KVER_UNAME}"
        if [[ ${ARCH} == s390x ]]; then
            The stdout should include "zipl"
            The stdout should include "✅ Grubby workaround for s390x completed"
        fi
        The stdout should include "ℹ️ running depmod to check for problems"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/depmod-check PASS 0"
        The status should be success
    End

    It "can detect depmod issues with $1"
        export KPKG_VAR_SOURCE_PACKAGE_NAME=$1
        export KPKG_VAR_PACKAGE_NAME=$2
        export KPKG_VAR_VARIANT_SUFFIX=$3
        export ARCH=$4
        export KVER_RPM=$5
        export EXPECTED_KVER_UNAME=$6
        export YUM=dnf
        export KPKG_URL=https://some-url
        echo "${KVER_RPM}" > /var/tmp/kpkginstall/KPKG_KVER
        export MOCKED_DEPMOD="depmod: WARNING: /lib/modules/${EXPECTED_KVER_UNAME}/kernel/sound/soc/soc-utils-test.ko.xz needs unknown symbol kunit_do_failed_assertion"
        When call rpm_install
        The first line should equal "ℹ️ rpm_install: Extracting kernel version from ${KPKG_URL}"
        The third line should equal "✅ Kernel version is ${KVER_RPM}"
        The stdout should include "✅ Downloaded ${KPKG_VAR_PACKAGE_NAME}-${KVER_RPM} successfully"
        The stdout should include "✅ Installed ${KPKG_VAR_PACKAGE_NAME}-${KVER_RPM} successfully"
        The stdout should include "ℹ️ running depmod to check for problems"
        The stdout should include "rstrnt-report-result -o /tmp/depmod.log distribution/kpkginstall/depmod-check WARN 7"
        The status should be success
    End
End

Describe 'kpkginstall: rpm_install automotive'
    Parameters
        # SOURCE_PACKAGE_NAME    PACKAGE_NAME             VARIANT_SUFFIX ARCH     KVER_RPM                         EXPECTED_KVER_UNAME
        # kernel source package with variants
        kernel-automotive        kernel-automotive        ""             aarch64  "5.14.0-298.261.el9iv.aarch64"  "5.14.0-298.261.el9iv.aarch64"
        kernel-automotive-debug  kernel-automotive-debug  ""             aarch64  "5.14.0-298.261.el9iv.aarch64"  "5.14.0-298.261.el9iv.aarch64"
    End
    setup() {
        mkdir -p /var/tmp/kpkginstall/vars
    }
    cleanup() {
        rm -rf /var/tmp/kpkginstall
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    cki_is_kernel_automotive() {
        return 0
    }
    It "can install $2-$5"
        export KPKG_VAR_SOURCE_PACKAGE_NAME=$1
        export KPKG_VAR_PACKAGE_NAME=$2
        export KPKG_VAR_VARIANT_SUFFIX=$3
        export ARCH=$4
        export KVER_RPM=$5
        export EXPECTED_KVER_UNAME=$6
        export YUM=dnf
        export RPM_OSTREE=rpm-ostree
        export KPKG_URL=https://some-url
        echo "${KVER_RPM}" > /var/tmp/kpkginstall/KPKG_KVER
        When call rpm_install
        The first line should equal "ℹ️ rpm_install: Extracting kernel version from ${KPKG_URL}"
        The third line should equal "✅ Kernel version is ${KVER_RPM}"
        The line 4 should equal "ℹ️ Test automotive installed kernel"
        The stdout should include "✅ Downloaded ${KPKG_VAR_PACKAGE_NAME}-${KVER_RPM} successfully"
        The stdout should include "✅ Installed ${KPKG_VAR_PACKAGE_NAME}-${KVER_RPM} successfully"
        The status should be success
    End
End
Describe 'kpkginstall: rpm_extra_package_install'
    setup() {
        mkdir -p /var/tmp/kpkginstall
    }
    cleanup() {
        rm -rf /var/tmp/kpkginstall
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    Parameters
        # SOURCE_PACKAGE_NAME    PACKAGE_NAME      KVER
        kernel                   kernel            "4.18.0-442.el8.s390x"
    End

    K_GetRunningKernelRpmSubPackageNVR() {
        echo "K_GetRunningKernelRpmSubPackageNVR $*"
    }

    It "can install extra packages for $2-$3"
        export KPKG_VAR_SOURCE_PACKAGE_NAME=$1
        export KPKG_VAR_PACKAGE_NAME=$2
        export KVER=$3
        export YUM=dnf
        When call rpm_extra_package_install
        The line 1 should include "✅ Installed K_GetRunningKernelRpmSubPackageNVR devel successfully"
        The line 2 should include "✅ Installed K_GetRunningKernelRpmSubPackageNVR modules-internal successfully"
        The line 3 should include "✅ Installed K_GetRunningKernelRpmSubPackageNVR headers successfully"
        The status should be success
    End
End

Describe 'kpkginstall: main - install kernel'
    Parameters
        kernel "$KERNEL_RPM_URL"
        kernel "$KERNEL_TGZ_URL"
        kernel-rt "$KERNEL_REALTIME_RPM_URL"
        kernel-64k "$KERNEL_64k_RPM_URL"
        kernel "$KERNEL_DEBUG_PARAM_RPM_URL"
        kernel "$KERNEL_DEBUG_RPM_URL"
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
        dmesg(){
            echo "dmesg $*"
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
        echo "${KVER_UNAME}"
    fi
    if [ "$1" == "-i" ];then
        echo "${ARCH}"
    fi
}
select_yum_tool() {
    echo "select_yum_tool"
    return 0
}
rpm_extra_package_install() {
    echo "rpm_extra_package_install"
    return 0
}
get_kpkg_ver() {
    return 0
}
cat(){
    if [[ $1 == /var/* ]]; then
        command cat "$@"
    else
        echo "cat $*"
    fi
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
        # URL                                      SOURCE_PACKAGE_NAME      PACKAGE_NAME      VARIANT_SUFFIX ARCH     KVER_RPM                                 KVER_UNAME
        # kernel source package with variants
        "${KERNEL_RPM_URL}"                        kernel                   kernel            ""             x86_64   "4.18.0-442.el8.x86_64"                  "4.18.0-442.el8.x86_64"
        "${KERNEL_64k_RPM_URL}"                    kernel                   kernel-64k        -64k           aarch64  "5.14.0-243.1820_756592390.el9.aarch64"  "5.14.0-243.1820_756592390.el9.aarch64+64k"
        "${KERNEL_DEBUG_RPM_URL}"                  kernel                   kernel-debug      -debug         s390x    "4.18.0-442.el8.s390x"                   "4.18.0-442.el8.s390x+debug"
        "${KERNEL_RT_RPM_URL}"                     kernel                   kernel-rt         -rt            x86_64   "4.18.0-442.el8.x86_64"                  "4.18.0-442.el8.x86_64+rt"
        # realtime branch
        "${KERNEL_REALTIME_RPM_URL}"               kernel-rt                kernel-rt         ""             s390x    "4.18.0-442.el8.s390x"                   "4.18.0-442.el8.s390x"
        # debug jobs
        "${KERNEL_DEBUG_PARAM_RPM_URL}"            kernel                   kernel-rt-debug   -rt-debug      x86_64   "5.14.0-276.el9.x86_64"                  "5.14.0-276.el9.x86_64+rt-debug"
        # realtime branch debug jobs
        "${KERNEL_REALTIME_DEBUG_PARAM_RPM_URL}"   kernel-rt                kernel-rt-debug   -debug         x86_64   "5.14.0-276.el9.x86_64"                  "5.14.0-276.el9.x86_64+debug"
        # tarballs
        "${KERNEL_TGZ_URL}"                        kernel                   kernel            ""             x86_64   "6.1.0-rc7"                              "6.1.0-rc7"
    End
    setup() {
        mkdir -p /var/tmp/kpkginstall/vars
    }
    prepare() {
        # skip the workaround from cross-compiling
        mkdir -p "/usr/src/kernels/${KVER_UNAME}/scripts/basic/"
        touch "/usr/src/kernels/${KVER_UNAME}/scripts/basic/fixdep"
    }
    cleanup() {
        rm -rf /var/tmp/kpkginstall
        rm -rf "/usr/src/kernels/${KVER_UNAME}/scripts/basic/"
    }
    BeforeEach 'setup'
    AfterEach 'cleanup'
    export REBOOTCOUNT=1

    It "installed with $1"
        KPKG_URL=$1
        KPKG_VAR_SOURCE_PACKAGE_NAME=$2
        KPKG_VAR_PACKAGE_NAME=$3
        KPKG_VAR_VARIANT_SUFFIX=$4
        ARCH=$5
        KVER=$6
        KVER_UNAME=$7
        prepare
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "Running kernel release:  ${KVER_UNAME}"
        The stdout should include "✅ Found the correct kernel release running!"
        The stdout should include "rpm_extra_package_install"
        The stdout should include "sysctl kernel.panic_on_oops"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/dmesg-check PASS 0"
        The stdout should include "rstrnt-report-result -o /tmp/journalctl.log distribution/kpkginstall/journalctl-check PASS 0"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/reboot PASS"
        The status should be success
    End

    It "can detect Call Traces on dmesg with $1"
        KPKG_URL=$1
        KPKG_VAR_SOURCE_PACKAGE_NAME=$2
        KPKG_VAR_PACKAGE_NAME=$3
        KPKG_VAR_VARIANT_SUFFIX=$4
        ARCH=$5
        KVER=$6
        KVER_UNAME=$7
        export MOCKED_DMESG="Call Trace:"
        prepare
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel release running!"
        The stdout should include "sysctl kernel.panic_on_oops"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/dmesg-check WARN 7"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/reboot FAIL"
        The status should be success
    End

    It "can detect Call Traces on journalctl with $1"
        KPKG_URL=$1
        KPKG_VAR_SOURCE_PACKAGE_NAME=$2
        KPKG_VAR_PACKAGE_NAME=$3
        KPKG_VAR_VARIANT_SUFFIX=$4
        ARCH=$5
        KVER=$6
        KVER_UNAME=$7
        export MOCKED_JOURNALCTL="Call Trace:"
        prepare
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel release running!"
        The stdout should include "sysctl kernel.panic_on_oops"
        The stdout should include "rstrnt-report-result -o /tmp/journalctl.log distribution/kpkginstall/journalctl-check WARN 7"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/reboot FAIL"
        The status should be success
    End
End

Describe 'kpkginstall: main - check installed kernel with cross compiling'
    setup(){
        mkdir -p /var/tmp/kpkginstall/vars
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
        KVER_UNAME="$2"
        echo "$1" > /var/tmp/kpkginstall/vars/KPKG_VAR_PACKAGE_NAME
        # Make sure it will execute cross compiling path
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        # Create a dummy config to pass compiler/linker detection
        {
            echo "CONFIG_CC_IS_GCC=y"
            echo "CONFIG_LD_IS_BFD=y"
        } >/usr/src/kernels/"$KVER"/.config
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel release running!"
        The stdout should include "ℹ️ Workaround for cross compiling non x86_64 kernels"
        The stdout should include "sysctl kernel.panic_on_oops"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/dmesg-check PASS 0"
        The stdout should include "rstrnt-report-result -o /tmp/journalctl.log distribution/kpkginstall/journalctl-check PASS 0"
        The stdout should include "rstrnt-report-result distribution/kpkginstall/reboot PASS"
        The status should be success
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    End

    It "installed with KPKG_URL=$3 with cross compiling fails on olddefconfig"
        KVER="$2"
        #KVER is updated with in the main function
        KVER_UNAME="$2"
        export OLDERCONFIG_EXIT_CODE=1
        echo "$1" > /var/tmp/kpkginstall/vars/KPKG_VAR_PACKAGE_NAME
        # Make sure it will execute cross compiling path
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        # Create a dummy config to pass compiler/linker detection
        {
            echo "CONFIG_CC_IS_GCC=y"
            echo "CONFIG_LD_IS_BFD=y"
        } >/usr/src/kernels/"$KVER"/.config
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel release running!"
        The stdout should include "ℹ️ Workaround for cross compiling non x86_64 kernels"
        The stdout should not include "make -C /usr/src/kernels/$KVER_UNAME modules_prepare"
        The stdout should include "cki_abort_recipe Failed applying cross compiling workaround WARN"
        The status should be success
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    End

    It "installed with KPKG_URL=$3 with cross compiling fails on modules_prepare"
        KVER="$2"
        #KVER is updated with in the main function
        KVER_UNAME="$2"
        export MODULES_PREPARE_EXIT_CODE=1
        echo "$1" > /var/tmp/kpkginstall/vars/KPKG_VAR_PACKAGE_NAME
        # Make sure it will execute cross compiling path
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        # Create a dummy config to pass compiler/linker detection
        {
            echo "CONFIG_CC_IS_GCC=y"
            echo "CONFIG_LD_IS_BFD=y"
        } >/usr/src/kernels/"$KVER"/.config
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel release running!"
        The stdout should include "ℹ️ Workaround for cross compiling non x86_64 kernels"
        The stdout should not include "make -C /usr/src/kernels/$KVER_UNAME scripts"
        The stdout should include "cki_abort_recipe Failed applying cross compiling workaround WARN"
        The status should be success
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    End

    It "installed with KPKG_URL=$3 with cross compiling fails on scripts"
        KVER="$2"
        #KVER is updated with in the main function
        KVER_UNAME="$2"
        export SCRIPTS_EXIT_CODE=1
        echo "$1" > /var/tmp/kpkginstall/vars/KPKG_VAR_PACKAGE_NAME
        # Make sure it will execute cross compiling path
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
        # Create a dummy config to pass compiler/linker detection
        {
            echo "CONFIG_CC_IS_GCC=y"
            echo "CONFIG_LD_IS_BFD=y"
        } >/usr/src/kernels/"$KVER"/.config
        When call main
        The first line should equal "ℹ️ REBOOTCOUNT is 1"
        The stdout should include "✅ Found the correct kernel release running!"
        The stdout should include "ℹ️ Workaround for cross compiling non x86_64 kernels"
        The stdout should include "cki_abort_recipe Failed applying cross compiling workaround WARN"
        The status should be success
        rm -rf /usr/src/kernels/"$KVER"/scripts/basic/
    End
End
