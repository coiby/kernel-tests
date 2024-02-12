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

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

# Include environment and libraries
source "$CDIR"/../../cki_lib/libcki.sh || exit 1

# Test parameters to use some specific version of stqe tests or libsan library
STQE_STABLE_VERSION=${STQE_STABLE_VERSION:-""}
LIBSAN_STABLE_VERSION=${LIBSAN_STABLE_VERSION:-""}

get_release() {
  source /etc/os-release
  export DISTRO_FAMILY=$ID                                # e.g. 'fedora', 'rhel'
  export DISTRO_VERSION=$VERSION_ID                       # e.g. '36', '8.6'
  export DISTRO_MIN=$DISTRO_FAMILY-$DISTRO_VERSION        # e.g. 'rhel-9.1', 'fedora-36'
  DISTRO_MAJ=$(echo "$DISTRO_MIN" | cut -d '.' -f 1)
  export DISTRO_MAJ                                       # e.g. 'rhel-9', 'fedora-36
}

stqe_init() {
  get_release
  pkg_mgr=$(dnf >/dev/null 2>&1 && echo dnf || echo yum)
  stqe_path="/opt/stqe-venv"
  python='python3'
  STQE_PYTHON=$stqe_path/bin/python
  STQE_TEST_EXE=$stqe_path/bin/stqe-test

  if [[ $DISTRO_MAJ == 'rhel-7' ]]; then
    $pkg_mgr install -y python3-pip python3-devel gcc
    # Lightweight versions with minimal dependencies
    STQE_STABLE_VERSION=0.2.0b3
    LIBSAN_STABLE_VERSION=0.5.0b5

  # upgrade to python39 when on rhel-8
  elif [[ $DISTRO_MAJ == 'rhel-8' ]]; then
    python='python3.9'
    if ! $STQE_PYTHON -m pip -V >/dev/null 2>&1; then
      $pkg_mgr install -y python39-devel python39-pip
    fi
  else  # assume python>=3.9
    if ! $STQE_PYTHON -m pip -V >/dev/null 2>&1; then
      $pkg_mgr install -y python3-devel python3-pip
    fi
  fi

  # if stqe-test executable already works do nothing
  if ! $STQE_TEST_EXE --help >/dev/null 2>&1; then
    if [[ $ARCH == 'ppc64le' || $ARCH == 's390x' ]]; then
      $pkg_mgr install -y gcc python3-ruamel-yaml-clib --skip-broken  # ruamel.yaml.clib needs to either be compiled or an already installed rpm
    fi
    # create virtualenv
    $python -m pip install virtualenv
    $python -m venv $stqe_path --system-site-packages  # site-packages might be needed for some tests
    $stqe_path/bin/pip install -U pip wheel
    if [[ -n $LIBSAN_STABLE_VERSION ]]; then
      $stqe_path/bin/pip install libsan=="$LIBSAN_STABLE_VERSION"
    fi
    if [[ -n $STQE_STABLE_VERSION ]]; then
      cki_run "$stqe_path/bin/pip install stqe==$STQE_STABLE_VERSION" ||
        cki_abort_task "Fail to install stqe==$STQE_STABLE_VERSION"
    else
      cki_run "$stqe_path/bin/pip install stqe" ||
        cki_abort_task "Fail to install stqe"
    fi
  fi

source $stqe_path/bin/activate
export STQE_PYTHON  # Python interpreter to use with libsan, stqe libs
export STQE_TEST_EXE  # stqe-test i.e. $STQE_TEST_EXE run -t <test>
return 0
}
