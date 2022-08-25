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

. ../include/include.sh

TEST="/kcov/finalize"

log "loading config from $KCOV_CONF"
# set KCOV_BASE_INFO, KCOV_TEST_INFO, KCOV_ALL_INFO, KCOV_COMBINED_INFO
load_config

log "processing coverage data for all cases."

FILE_OPTION_LIST=$(awk 1 ORS=' -a ' $KCOV_INFO_LIST)
FILE_OPTION_LIST=" -a ${FILE_OPTION_LIST%' -a '}"
lcov $FILE_OPTION_LIST -o $KCOV_COMBINED_INFO
cki_upload_log_file $KCOV_COMBINED_INFO

pass

