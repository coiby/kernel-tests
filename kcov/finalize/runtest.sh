#!/bin/bash

# Copyright (c) 2010 Red Hat, Inc. All rights reserved. This copyrighted material 
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
# Author: Hushan Jia <hjia@redhat.com>

. /usr/bin/rhts_environment.sh

. ../include/include.sh

log "loading config from $KCOV_CONF"
# set KCOV_BASE_INFO, KCOV_TEST_INFO, KCOV_ALL_INFO, KCOV_COMBINED_INFO
load_config

log "processing coverage data for all cases."

HTMLDIR=$(mktemp -d $TDIR/kcov.XXXX)
tag="J:${JOBID}-${HOSTNAME%.redhat.com}-${TASKID}"



log "Generate html archive."
ALL_INFO_FILES=$(cat $KCOV_INFO_LIST | tr '\n' ' ')
FILE_OPTION_LIST=$(awk 1 ORS=' -a ' $KCOV_INFO_LIST)
FILE_OPTION_LIST=" -a ${FILE_OPTION_LIST%' -a '}"
lcov $FILE_OPTION_LIST -o $KCOV_COMBINED_INFO
rhts-submit-log -l $KCOV_COMBINED_INFO

if [[ $NO_HTML != 'true' ]]; then
	genhtml --show-details --title "Coverage of kernel tests on $(uname -r)" --legend --highlight -o $HTMLDIR $KCOV_COMBINED_INFO
	cp $KCOV_COMBINED_INFO $HTMLDIR

	tar -C $TDIR -zcf $TDIR/kcov_all-${tag}.tgz $(basename $HTMLDIR)
	rhts-submit-log -l $TDIR/kcov_all-${tag}.tgz

	[ -n "$NFS_SHARE" ] && {
		MP=/nfs-kcov
		UPDIR=$(uname -r)/$TASKNAME
		log "{Info} upload kcov result file to $NFS_SHARE / $UPDIR"
		mkdir $MP
		mount $NFS_SHARE /$MP && mkdir -p $MP/$UPDIR &&
			cp $TDIR/kcov_all-${tag}.tgz  $MP/$UPDIR/.
		ls -l $MP/$UPDIR
		umount $MP
	}
fi

pass

