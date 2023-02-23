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
# TODO DO NOT MERGE, TESTING DEV VERSIONS
STQE_STABLE_VERSION=${STQE_STABLE_VERSION:-"0.2.1.dev2"}
LIBSAN_STABLE_VERSION=${LIBSAN_STABLE_VERSION:-"0.5.0.dev2"}

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
  STQE_PYTHON=$stqe_path/bin/python
  STQE_TEST_EXE=$stqe_path/bin/stqe-test

  # Use rh-python38 from scl when on rhel-7
  if [[ $DISTRO_MAJ == 'rhel-7' ]]; then
    STQE_PYTHON="/usr/bin/scl enable rh-python38 -- $stqe_path/bin/python"
    python='python3.8'
    # In case it stqe has already been installed
    if ! $STQE_TEST_EXE --help >/dev/null 2>&1; then
      cat > /etc/yum.repos.d/rhscl3.repo <<EOF
[rhscl]
name=rhscl
baseurl=http://download.devel.redhat.com/rhel-7/rel-eng/latest-RHSCL-3-RHEL-7/compose/Server/\$basearch/os/
enabled=0
gpgcheck=0
skip_if_unavailable=1
EOF
      cki_run "$pkg_mgr install -y rh-python38-python-devel --enablerepo=rhscl" ||  # devel in case we need to compile
        cki_abort_task "Fail to install rh-python38 from rhscl"
      source scl_source enable rh-python38
    fi
  # upgrade to python39 when on rhel-8
  elif [[ $DISTRO_MAJ == 'rhel-8' ]]; then
    python='python3.9'
    if ! $STQE_PYTHON -m pip -V >/dev/null 2>&1; then
      $pkg_mgr install -y python39-devel python39-pip
    fi
  else
  # assume python>=3.9
    python='python3'
    if ! $STQE_PYTHON -m pip -V >/dev/null 2>&1; then
      $pkg_mgr install -y python3-devel python3-pip
    fi
  fi

  # if stqe-test executable already works do nothing
  if ! $STQE_TEST_EXE --help >/dev/null 2>&1; then
    if [[ $ARCH == 'ppc64le' || $ARCH == 's390x' ]]; then
      $pkg_mgr install -y gcc  # ruamel.yaml.clib needs compilation
    fi
    # create virualenv
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
