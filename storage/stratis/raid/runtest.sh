#!/bin/sh
# Copyright (c) 2022 Red Hat, Inc. All rights reserved. This copyrighted
# material is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
# USA.
#
# Author: Filip Suba   <fsuba@redhat.com>

# echo $ENV_PARAMS
export STRATIS_DBUS_TIMEOUT=500000

# OS=$(cat /etc/*release | grep VERSION_ID | cut -c13)

# STRATIS_VERSION=3
# if [ "$OS" == 8 ]; then
#  STRATIS_VERSION=2
# fi

# if [ ! "$RAID_LEVEL" ]; then
#  setup="--setup raid/0"
# else
#  setup="--setup raid/$RAID_LEVEL"
# fi

# stqe-test run --fmf --filter component:stratis --filter stratis_version:$STRATIS_VERSION $setup $ENV_PARAMS
stqe-test run --fmf --filter component:stratis --filter tags:single_device --filter tier:1 --setup raid/0
for key in $(stratis --propagate key list | grep -v 'Key Description'); do
  stratis --propagate key unset "$key"
done
#############gernal stratis report after testing #####
stratis --propagate report engine_state_report
