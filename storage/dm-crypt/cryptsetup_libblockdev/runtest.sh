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
# Author: guazhang  <guazhang@redhat.com>

# Include Beaker environment
. ../../../cki_lib/libcki.sh || exit 1 
. /usr/share/beakerlib/beakerlib.sh || cki_abort_task "fail to include beakerlib.sh" 
. ../../include/libstqe.sh || cki_abort_task "fail to include libstqe.sh"

function install_libblockdev(){
    YUM=$(cki_get_yum_tool)
    for i in "libblockdev-utils libblockdev libblockdev-lvm libblockdev-kbd libblockdev-dm libblockdev-fs libblockdev-loop libblockdev-mpath libblockdev-swap libblockdev-nvdimm libblockdev-lvm-dbus libblockdev-mdraid libblockdev-crypto libblockdev-part libblockdev-plugins-all python3-blockdev python3-gobject-base"; do
        cki_run "$YUM install -y $i >/dev/null 2>&1"
        if [[ $? !=  0 ]];then
            cki_print_warning "Could not install package $i; exit"
            exit 1
        fi
    done
}

function check_python_env(){
    if [[ ! -f luks_main.py ]];then
        cki_print_warning "Could not find the luks_main.py file, exit"
        exit 1
    fi
    $PY -c "import libsan" 
    if [[ $? != 0 ]];then
        cki_print_warning "Could not import python module libsan, exit"
        exit 1
    fi
}

PY="python3"

# stqe_init will abort the task if fails to run
stqe_init
install_libblockdev
check_python_env
$PY luks_main.py
rc=$?
exit $rc
