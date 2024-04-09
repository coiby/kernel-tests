#!/bin/bash

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
# Author: Zhouping Liu   <zliu@redhat.com>

function verify_tune_value()
{
        if [ $# -ne 2 ]; then
                echo "Usage: verify_tune [TUNE_FILE] [TUNE_VALUE]"
                echo ${OLD_DROPCACHES} > ${TUNE_FILE}
                exit 1;
        fi

        TUNE_FILE=$1
        TUNE_VALUE=$2

        if [ "${TUNE_FILE}" = "/proc/sys/vm/drop_caches" ]; then
            TEST_TUNE=$(dmesg | awk -F "drop_caches: "  '/drop_caches/ {print $2}')
        else
            TEST_TUNE=$(cat ${TUNE_FILE})
        fi
        if [ ${TEST_TUNE} -ne ${TUNE_VALUE} ]; then
                echo "TestError: Set value to ${TUNE_FILE} Failed"
                echo ${OLD_DROPCACHES} > ${TUNE_FILE}
                exit 1
        fi
}

function check_file_exist()
{
    if [ $# -ne 1 ]; then
        echo "Usage: check_file_exist [TUNE_FILE]"
        exit 1;
    fi

    TUNE_FILE=$1
    if ! [ -f ${TUNE_FILE} ]; then
        echo "TestError: No this tune file ${TUNE_FILE}"
        exit 1;
    fi
}

function set_tune_value()
{
    if [ $# -ne 1 ]; then
        echo "Usage: set_tune_value [TUNE_FILE] [TUNE_VALUE]"
        exit 1;
    fi

    TUNE_FILE=$1
    TUNE_VALUE=$2
    echo $1 > $TUNE_VALUE $TUNE_FILE
}
