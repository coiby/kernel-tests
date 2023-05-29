#!/bin/sh

# Copyright (c) 2006 Red Hat, Inc. All rights reserved. This copyrighted material
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
# Author: Zhaojuan Guo  <zguo@redhat.com>

# include beaker environment and common libraries
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
#. "$CDIR"/../common/rdma-qa.sh || exit 400
. "$CDIR"/../../common/python_rdma_qe_lib.sh || exit 255

# start test
# show system info
RQA_system_info_for_debug

# set up python-rdma-qe module
rdmaqe_init

# run the main.py
${RDMAQE_PYTHON} main.py
