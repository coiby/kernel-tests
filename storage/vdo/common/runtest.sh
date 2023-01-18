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
# Author: Filip Suba <fsuba@redhat.com>

# This requires some default $ENV_PARAMS, for example setup.
# export ENV_PARAMS=" --setup=iscsi" for example
# See more options in 'stqe-test --help'

# need to get OS version for later filtering. This works only for RHEL though, as there are no Fedora filters...
# this is used in compose filter: '--filter compose:RHEL-$OS'
# OS=`cat /etc/*release | grep VERSION_ID | cut -c13`

if [ ! "$COMPONENT" ]; then
  component_filter="--filter component:kmod-kvdo|component:vdo"
else
  component_filter="--filter component:$COMPONENT"
fi

command="stqe-test run --fmf $component_filter $ENV_PARAMS"
echo "$command"

"$command"
