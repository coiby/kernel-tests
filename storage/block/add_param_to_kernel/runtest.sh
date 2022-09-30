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
# Author: guazhang <guazhang@redhat.com>

FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)
 
# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh     || exit 1
. /usr/share/beakerlib/beakerlib.sh         || exit 1

#KERNEL_OPS="scsi_mod.use_blk_mq=1,intel_pstate=disable"

python3 -c "import libsan; import stqe"
if [ $? == 0  ];then
    rhts-run-simple-test add_param_to_kernel "python3 ./add_param_to_kernel.py --kernel_ops=$KERNEL_OPS"
    EXIT_CODE=$?
else
    rhts-run-simple-test add_param_to_kernel "python2 ./add_param_to_kernel.py --kernel_ops=$KERNEL_OPS"
    EXIT_CODE=$?
fi
exit $EXIT_CODE
