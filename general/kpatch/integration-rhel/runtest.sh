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

KPATCH_SLOW=${KPATCH_SLOW:-0}
KPATCH_UNIT=${KPATCH_UNIT:-1}
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

kpatchdir="$(pwd)/kpatch"

if [ -n "${RSTRNT_REBOOTCOUNT}" ]; then
  if [ "${RSTRNT_REBOOTCOUNT}" -gt "0" ]; then
    if cd "${kpatchdir}"; then
      KPATCH_COMMIT_DESCRIPTION="$(git describe --all)"
      KPATCH_COMMIT_ID="$(git rev-parse HEAD)"
    fi

    console_log="console.log"
    console_log_url="${BEAKER_HUB_URL}/recipes/${BEAKER_RECIPE_ID}/logs/console.log"
    curl --insecure --location --output "${console_log}" "${console_log_url}"
    send_mail "rebooted" "${console_log}"
    test_fail "rebooted" "1"
    exit 1
  fi
fi

echo "slow: ${KPATCH_SLOW}"
echo "unit: ${KPATCH_UNIT}"
echo "git: ${KPATCH_GIT}"
echo "revision: ${KPATCH_REV}"
echo "mail-from: ${MAIL_FROM}"
echo "mail-to: ${MAIL_TO}"

git clone --recursive "${KPATCH_GIT}" | tee "${OUTPUTFILE}"
rc=${PIPESTATUS[0]}
if [ "${rc}" -ne 0 ]; then
  test_fail "setup" "${rc}"
  exit 1
fi

cd "${kpatchdir}"
rc=$?
if [ "${rc}" -ne 0 ]; then
  test_fail "setup" "${rc}"
  exit 1
fi

git fetch origin +refs/pull/*:refs/pull/*
git checkout -f "${KPATCH_REV}" | tee -a "${OUTPUTFILE}"
rc=${PIPESTATUS[0]}
if [ "${rc}" -ne 0 ]; then
  test_fail "setup" "${rc}"
  exit 1
fi

KPATCH_COMMIT_DESCRIPTION="$(git describe --all)"
KPATCH_COMMIT_ID="$(git rev-parse HEAD)"

source "${kpatchdir}/test/integration/lib.sh"

kpatch_dependencies | tee -a "${OUTPUTFILE}"
kpatch_set_ccache_max_size 10G | tee -a "${OUTPUTFILE}"

test_pass "setup"

if [ "${KPATCH_UNIT}" == "1" ]; then
  UNIT_LOG="unit.log"

  git submodule update | tee "${OUTPUTFILE}"
  make unit 2>&1 | tee "${UNIT_LOG}" | tee -a "${OUTPUTFILE}"
  rc=${PIPESTATUS[0]}

  rstrnt-report-log -l "${UNIT_LOG}"
  if [ "$rc" -eq 0 ]; then
    test_pass "unit"
  else
    send_mail "unit" "${UNIT_LOG}"
    test_fail "unit" "${rc}"
  fi
fi

# Beaker exports arch as uname -m which confuses kernel build a lot
export -n ARCH

if [ "${KPATCH_SLOW}" -eq 1 ]; then
  make integration-slow KPATCH_BUILD_OPTS="$KPATCH_BUILD_OPTS" 2>&1 | tee "${OUTPUTFILE}"
else
  make integration-quick KPATCH_BUILD_OPTS="$KPATCH_BUILD_OPTS" 2>&1 | tee "${OUTPUTFILE}"
fi

rc=${PIPESTATUS[0]}

for file in "${kpatchdir}"/test/integration/*.log; do
  rstrnt-report-log -l "${file}"
done

if [ "$rc" -eq 0 ]; then
  test_pass "integration"
else
  send_mail "integration" "${kpatchdir}/test/integration/*.log"
  test_fail "integration" "${rc}"
fi
