#!/bin/bash
#
# Copyright (c) 2019-2021 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

FILE=$(readlink -f "${BASH_SOURCE[@]}")
CDIR=$(dirname "$FILE")

# Include environment and libraries
source "$CDIR"/../../cki_lib/libcki.sh ||
  cki_abort_task "fail to include libcki.sh"

# Test parameters to use some specific version of stqe tests or libsan library
STQE_STABLE_VERSION=${STQE_STABLE_VERSION:-""}
LIBSAN_STABLE_VERSION=${LIBSAN_STABLE_VERSION:-""}

function get_release() {
  source /etc/os-release
  export DISTRO_FAMILY=$ID                                # e.g. 'fedora', 'rhel'
  export DISTRO_VERSION=$VERSION_ID                       # e.g. '36', '8.6'
  export DISTRO_MIN=$DISTRO_FAMILY-$DISTRO_VERSION        # e.g. 'rhel-9.1', 'fedora-36'
  DISTRO_MAJ=$(echo "$DISTRO_MIN" | cut -d '.' -f 1)
  export DISTRO_MAJ                                       # e.g. 'rhel-9', 'fedora-36
}

function stqe_init {
  typeset pip="python3 -m pip"
  typeset pkg_mgr=$(dnf >/dev/null 2>&1 && echo dnf || echo yum)

  # augeas-libs needed for RHEL-7, netifaces needed for aarch64
  cki_run "$pkg_mgr install -y --skip-broken python3-pip python3-wheel python3-augeas augeas-libs python3-netifaces" ||
    cki_abort_task "FAIL: Could not install framework dependencies"
  # ppc64, ppc64le, and s390x need to compile some python modules for now
  if [[ $ARCH == 'ppc64' || $ARCH == 'ppc64le' || $ARCH == 's390x' ]]; then
    cki_run "$pkg_mgr install -y gcc cmake openssl-devel python3-devel libffi-devel zlib-devel" ||
      cki_abort_task "FAIL: Could not install framework dependencies"
  fi

  # Needed to install ruamel.yaml.clib from source, can be removed if aarch64 wheel is available
  if [[ $ARCH == 'aarch64' ]]; then
    cki_run "$pkg_mgr install -y gcc python3-devel" ||
      cki_abort_task "FAIL: Could not install cffi from source on ppc64le RHEL-7"
  fi

  # Check if we have pip>=20, install 20.3 if not
  if [[ $($pip -V | cut -f 2 -d ' ' | cut -f 1 -d '.') -lt 20 ]]; then
    cki_run "$pip install -U pip==20.3" ||
      cki_abort_task "FAIL: Could not install pip==20.3!"
  fi

  # Workaround for python-augeas compiling bug on RHEL-7 ppc64le
  if [[ $ARCH == 'ppc64le' ]]; then
    cki_run "$pip install cffi --no-binary=cffi" ||
      cki_abort_task "FAIL: Could not install cffi from source on ppc64le RHEL-7"
  fi

  if [[ -n $LIBSAN_STABLE_VERSION ]]; then
    cki_run "$pip libsan==$LIBSAN_STABLE_VERSION" ||
      cki_abort_task "Fail to install libsan==$LIBSAN_STABLE_VERSION"
  fi

  if [[ -n $STQE_STABLE_VERSION ]]; then
    cki_run "$pip install stqe==$STQE_STABLE_VERSION --no-binary=stqe" ||
      cki_abort_task "Fail to install stqe==$STQE_STABLE_VERSION"
  else
    cki_run "$pip install stqe --no-binary=stqe" ||
      cki_abort_task "Fail to install stqe"
  fi
  cki_run "restorecon -Rv /usr/local/lib/python* /usr/lib/python*"

  return 0
}
