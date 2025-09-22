#!/bin/bash

# Copyright (c) 2014 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Artem Savkov <asavkov@redhat.com>

. ../include/lib.sh
set -x

# Create log
export OUTPUTFILE=${OUTPUTFILE:-$(mktemp /mnt/testarea/tmp.XXXXXX)}

BUILDDIR="/mnt/build"
KVER=${KVER:-linux-6.2}
KERNEL_TARBALL=${KERNEL_TARBALL:-}
if [ -z "$KERNEL_TARBALL" ] ; then
        KERNEL_TARBALL="${KVER}"
fi
KERNEL_TARBALL_PATH="${BUILDDIR}/${KERNEL_TARBALL}.tar.gz"
KERNEL_TARBALL_URL="${KERNEL_TARBALL_URL:-https://cdn.kernel.org/pub/linux/kernel/v6.x}/${KERNEL_TARBALL}.tar.gz"
KERNEL_PATCH_URL=${KERNEL_PATCH_URL:-}
KERNEL_SOURCE_PATH="${BUILDDIR}/${KERNEL_TARBALL}"
KPATCH_DIR="${BUILDDIR}/kpatch"

KPATCH_SLOW=${KPATCH_SLOW:-0}
KPATCH_UNIT=${KPATCH_UNIT:-1}
KPATCH_CHECK_CLANG=${KPATCH_CHECK_CLANG:-1}
KPATCH_GIT=${KPATCH_GIT:-https://github.com/dynup/kpatch.git}
KPATCH_REV=${KPATCH_REV:-HEAD}
KPATCH_COMMIT_DESCRIPTION=""
KPATCH_COMMIT_ID=""
KPATCH_BUILD_OPTS="${KPATCH_BUILD_OPTS:-}"

MAIL_FROM=${MAIL_FROM:-kernel-livepatching@redhat.com}
MAIL_TO=${MAIL_TO:-kernel-livepatching@redhat.com}

function send_mail()
{
        local type="${1}"
        local logs="${2}"

        local recipe_url="${BEAKER_HUB_URL}/recipes/${BEAKER_RECIPE_ID}"

        source /etc/os-release
        local subject="[${KPATCH_COMMIT_DESCRIPTION}] [kpatch/${type}] test failure on ${ID}-${VERSION_ID}.$(uname -m)"

        local att_opts

        for file in ${logs}; do
                gzip "${file}"
                att_opts+=" -a ${file}.gz"
        done

        local msg
        msg="repo: ${KPATCH_GIT}\n"
        msg+="rev: ${KPATCH_COMMIT_DESCRIPTION} (${KPATCH_COMMIT_ID})\n"
        if [[ "${KPATCH_COMMIT_DESCRIPTION}" =~ pull/[0-9]+/ ]]; then
                msg+="pr url: ${KPATCH_GIT%.git}/${KPATCH_COMMIT_DESCRIPTION%/*}\n"
        fi
        msg+="commit url: ${KPATCH_GIT%.git}/commits/${KPATCH_COMMIT_ID}\n"
        msg+="os: ${PRETTY_NAME}\n"
        msg+="uname: $(uname -a)\n"
        msg+="job url: ${recipe_url}\n"

        echo -e "${msg}" | mail ${att_opts} -r "${MAIL_FROM}" -s "${subject}" "${MAIL_TO}"
}

function prepare_dependencies()
{
        mkdir -p "${BUILDDIR}/.ccache"
        ln -sv "${BUILDDIR}/.ccache" "${HOME}/"
        dnf install -y git clang ccache

        source "${KPATCH_DIR}/test/integration/lib.sh"

        kpatch_dependencies | tee -a "${OUTPUTFILE}"
        kpatch_set_ccache_max_size 10G | tee -a "${OUTPUTFILE}"
        source /etc/profile.d/ccache.sh

        test_pass "dependencies"
}

function prepare_kernel_sources()
{
        if ! wget -O "${KERNEL_TARBALL_PATH}" "${KERNEL_TARBALL_URL}"; then
                test_fail "kernel_sources_wget" "${?}"
                exit 1
        fi

        if ! tar xf "${KERNEL_TARBALL_PATH}" -C "${BUILDDIR}"; then
                test_fail "kernel_sources_untar" "${?}"
                exit 1
        fi

        if [[ -n "${KERNEL_PATCH_URL}" ]]; then
                if ! wget -O "${KERNEL_SOURCE_PATH}/kernel.patch" "${KERNEL_PATCH_URL}"; then
                        test_fail "kernel_patch_wget" "${?}"
                        exit 1
                fi

                if ! patch --directory="${KERNEL_SOURCE_PATH}" -p1 < "${KERNEL_SOURCE_PATH}/kernel.patch"; then
                        test_fail "kernel_patch_apply" "${?}"
                        exit 1
                fi
        fi

        test_pass "kernel_sources"
}

function install_kernel()
{
        local compiler="${1}"

        if ! cp "config.${KVER}.${compiler}.$(uname -m)" "${KERNEL_SOURCE_PATH}/.config"; then
                test_fail "kernel_${compiler}_config" "${rc}"
                exit 1
        fi

        if ! cd "${KERNEL_SOURCE_PATH}"; then
                test_fail "kernel_${compiler}_cd" "${rc}"
                exit 1
        fi

        if [ "${compiler}" != "gcc" ]; then
                make CC="${compiler}" LLVM_IAS=0 -j"$(nproc)" 2>&1 | tee -a "${OUTPUTFILE}"
        else
                make -j"$(nproc)" 2>&1 | tee -a "${OUTPUTFILE}"
        fi

        rc=${PIPESTATUS[0]}
        if [ "${rc}" -ne 0 ]; then
                test_fail "kernel_${compiler}_build" "${rc}"
                exit 1
        fi

        make modules_install 2>&1 | tee -a "${OUTPUTFILE}"
        rc=${PIPESTATUS[0]}
        if [ "${rc}" -ne 0 ]; then
                test_fail "kernel_${compiler}_modules_install" "${rc}"
                exit 1
        fi

        make install 2>&1 | tee -a "${OUTPUTFILE}"
        rc=${PIPESTATUS[0]}
        if [ "${rc}" -ne 0 ]; then
                test_fail "kernel_${compiler}_install" "${rc}"
                exit 1
        fi

        grubby --set-default="/boot/vmlinuz-${KVER#linux-}" && rstrnt-reboot
}

function get_kpatch()
{
        local previous_dir=$(pwd)

        git clone --recursive "${KPATCH_GIT}" "${KPATCH_DIR}" | tee "${OUTPUTFILE}"
        rc=${PIPESTATUS[0]}
        if [ "${rc}" -ne 0 ]; then
                test_fail "kpatch_clone" "${rc}"
                exit 1
        fi

        if ! cd "${KPATCH_DIR}"; then
                test_fail "kpatch_cd" "${rc}"
                exit 1
        fi

        git fetch origin +refs/pull/*:refs/pull/*
        git checkout -f "${KPATCH_REV}" | tee -a "${OUTPUTFILE}"
        rc=${PIPESTATUS[0]}
        if [ "${rc}" -ne 0 ]; then
                test_fail "kpetch_checkout" "${rc}"
                exit 1
        fi

        test_pass "kpatch"

        cd "${previous_dir}" || exit 1
}

function kpatch_integration_tests()
{
        local prefix="${1}"
        local previous_dir=$(pwd)

        if ! cd "${KPATCH_DIR}"; then
                test_fail "integration_${prefix}_cd" "${rc}"
                exit 1
        fi

        uname -a

        KPATCH_COMMIT_DESCRIPTION="$(git describe --all)"
        KPATCH_COMMIT_ID="$(git rev-parse HEAD)"

        if [ "${KPATCH_SLOW}" -eq 1 ]; then
                make PATCH_DIR="${KVER}" KPATCH_BUILD_OPTS="$KPATCH_BUILD_OPTS -s ${KERNEL_SOURCE_PATH}" integration-slow 2>&1 | tee "${OUTPUTFILE}"
        else
                make PATCH_DIR="${KVER}" KPATCH_BUILD_OPTS="$KPATCH_BUILD_OPTS -s ${KERNEL_SOURCE_PATH}" integration-quick 2>&1 | tee "${OUTPUTFILE}"
        fi

        rc=${PIPESTATUS[0]}

        for file in "${KPATCH_DIR}"/test/integration/*.log; do
                newfile="$(dirname "${file}")/${prefix}_$(basename "${file}")"
                mv "${file}" "${newfile}"
                rstrnt-report-log -l "${newfile}"
        done

        if [ "$rc" -eq 0 ]; then
                test_pass "integration_${prefix}"
        else
                send_mail "integration" "${KPATCH_DIR}/test/integration/*.log"
                test_fail "integration_${prefix}" "${rc}"
        fi

        cd "${previous_dir}" || exit 1
}

# Beaker exports arch as uname -m which confuses kernel build a lot
export -n ARCH

if [[ -z "${RSTRNT_REBOOTCOUNT}" || "${RSTRNT_REBOOTCOUNT}" -eq "0" ]]; then
        get_kpatch
        prepare_dependencies
        prepare_kernel_sources
        install_kernel gcc
elif [[ "${RSTRNT_REBOOTCOUNT}" -eq "1" ]]; then
        test_pass "kernel_gcc_install"
        kpatch_integration_tests gcc
        if [[ "${KPATCH_CHECK_CLANG}" -ne "1" ]]; then
                exit
        fi
        install_kernel clang
elif [[ "${RSTRNT_REBOOTCOUNT}" -eq "2" ]]; then
        test_pass "kernel_clang_install"
        kpatch_integration_tests clang
fi
