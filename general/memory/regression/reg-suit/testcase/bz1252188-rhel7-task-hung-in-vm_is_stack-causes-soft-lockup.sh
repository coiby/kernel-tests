# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1251288
#   Description: [Private] Bug 1252188 - Task hung in vm_is_stack causing BUG soft lockup (edit) 
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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

function bz1252188()
{
    if rlIsRHEL 8; then
        python=/usr/libexec/platform-python
    else
        python=python
    fi
    export -f cgroup_create
    export -f __fix_cgroup_dir
    export -f cgroup_get_path
    if rlIsRHEL ">=7.2";then
	    case $(rlGetPrimaryArch) in
		x86_64|ppc64|ppc64le|s390x|aarch64)
			rlLogInfo "To see whether a softlockup will happen."
			$python $DIR_SOURCE/bz1252188.py &
			pid=$!
			sleep 60
			ps -L -p $pid -o tid,pid,ppid,gid,cgroup,args| tail -n 20
			kill -9 $pid
			rlLogInfo "Got here, check the dmesg, most possible we are not soft locked."
		    ;;
		*)
			rlLogInfo "$(uname -m) is not intended to be tested."
		    ;;
	    esac
    else
	rlLogWarning "The softlockup issue is resolved in RHEL-7.2 kernel-3.10.0-305.el7"
    fi
}
