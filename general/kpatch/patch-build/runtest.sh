#! /bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/kpatch/patch-build
#   Description: use upstream kpatch-build to build kpatch modules based
#                on an upstream commit.
#   Author: Roberto Bergantinos Corpas <rbergant@redhat.com>
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
. ../include/lib_build.sh
. ../include/lib.sh

# shellcheck disable=SC2034
BASIC_DONE=0
KPATCH_REV="${KPATCH_REV:-}"
KPATCH_REPO="${KPATCH_REPO:-https://github.com/dynup/kpatch.git}"
KPATCH_BUILD_OPTS="${KPATCH_BUILD_OPTS:-}"
KPATCH_SKIP_TEST="${KPATCH_SKIP_TEST:-}"
UPSTREAM_COMMIT_ID="${UPSTREAM_COMMIT_ID:-}"

rlJournalStart
    rlPhaseStartSetup
        rlRun "create_build_dir"
        download_kpatch_repo ${KPATCH_REPO} ${KPATCH_REV}
        pushd kpatch
        build_kpatch_setup
        popd
        rlRun "basic_build" || rlDie "build kpatch builder failed ..."
    rlPhaseEnd

    rlPhaseStartTest "Run kpatch-build against upstream patch"
        pushd kpatch
        rlRun "install_debuginfo" 0 "Installing debuginfo if needed"
        rlRun "get_src_rpm" 0 "Downloading SRC RPM"
        rlRun "get_patch_file ${UPSTREAM_COMMIT_ID}" 0 "Obtaining upstream patchfile"
        rlRun "kpatch-build/kpatch-build -r $(get_srpm_name) ${UPSTREAM_COMMIT_ID}.patch" 0
        rstrnt-report-log -l /root/.kpatch/build.log
    rlPhaseEnd
rlJournalEnd
