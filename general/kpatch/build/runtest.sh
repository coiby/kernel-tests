#! /bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/kpatch/build
#   Description: use upstream kpatch-build to build kpatch kernel modules.
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
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

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. lib_build.sh

# shellcheck disable=SC2034
BASIC_DONE=0
KPATCH_REV="${KPATCH_REV:-}"
KPATCH_REPO="${KPATCH_REPO:-https://github.com/dynup/kpatch.git}"
KPATCH_BUILD_OPTS="${KPATCH_BUILD_OPTS:-}"
KPATCH_SKIP_TEST="${KPATCH_SKIP_TEST:-}"
TEST_PATCH_PATH="test/integration"

rlJournalStart
    rlPhaseStartSetup
        rlRun "create_build_dir"
        if [ ! -e "kpatch/.git" ]; then
            if [ ! -z "${KPATCH_REV}" ]; then
                rlRun "git clone -b ${KPATCH_REV} ${KPATCH_REPO}" || rlDie
            else
                rlRun "git clone ${KPATCH_REPO}" || rlDie
                pushd kpatch
                KPATCH_REV=$(git describe --tags --abbrev=0)
                rlRun "git checkout ${KPATCH_REV}" || rlDie
                popd
            fi
        fi
        pushd kpatch
        rlRun "git describe --tags"
        rlRun "source test/integration/lib.sh"
        rlRun "kpatch_dependencies"
        rlRun "kpatch_set_ccache_max_size 10G"
        source /etc/os-release
        MA=$(cut -d '.' -f 1 <<< $VERSION_ID)
        MI=$(cut -d '.' -f 2 <<< $VERSION_ID)
        PREVIOUS_MI=$(( $MI-1 ))
        PREVIOUS_TARGET="${MA}.${PREVIOUS_MI}"
        [ ! -d ${TEST_PATCH_PATH}/${ID}-${VERSION_ID} ] && cp -R ${TEST_PATCH_PATH}/${ID}-${PREVIOUS_TARGET} ${TEST_PATCH_PATH}/${ID}-${VERSION_ID}
        if [ ! -z "${KPATCH_SKIP_TEST}" ]; then
            pushd test/integration/${ID}-${VERSION_ID}
            rm -rf ${KPATCH_SKIP_TEST}
            popd
        fi
        popd
        rlRun "basic_build" || rlDie "build kpatch builder failed ..."
        rlRun "start_module_collect_worker"
    rlPhaseEnd

    rlPhaseStartTest "Run kpatch integration tests (slow)"
        rlRun "unset ARCH" 0-255 "power64 can't parse ppc64le when kernel build"
        rlRun "RunBuildTest rlFileSubmit"
    rlPhaseEnd

    rlPhaseStartTest "Run kpatch integration tests (quick)"
        rlRun "RunCombinedBuild rlFileSubmit"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "end_module_collect_worker"
        umount ${KPATCH_MNT}
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText

