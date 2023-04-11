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

# python_rdma_qe_setup.sh is used to install and set up python-rdma-qe

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

#source "$CDIR"/../../cki_lib/libcki.sh || exit 400
source "$CDIR"/rdma-qa.sh || exit 255

# set Python interpreter
RQA_set_pyexec

rdmaqe_init() {
	rdmaqe_path="/opt/rdmaqe-venv"
	RDMAQE_PYTHON=$rdmaqe_path/bin/python

	source /etc/os-release
	local major=$(cut -d '.' -f 1 <<< $ID-$VERSION_ID)
	if [[ $major == "rhel-7" ]]; then
		${PKGINSTALL} python3-pip python3-devel gcc
	elif [[ $major == "rhel-8" ]]; then
		${PKGINSTALL} python39-devel python39-pip
	else
		${PKGINSTALL} python3-devel python3-pip
	fi

	${PYEXEC} -m pip install virtualenv
	${PYEXEC} -m venv $rdmaqe_path --system-site-packages
	$rdmaqe_path/bin/pip install -U pip wheel
	$rdmaqe_path/bin/pip install python-rdma-qe
	source $rdmaqe_path/bin/activate

	export RDMAQE_PYTHON
}
