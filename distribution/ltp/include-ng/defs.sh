#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

# Source the common test script helpers
. "${CDIR}"/../../../cki_lib/libcki.sh || exit 1
. "${CDIR}"/../kirk/kirk.sh || exit 1

if grep -iq "Automotive Stream Distribution release" /etc/system-release; then
	export CREATE_ENTRIES=1
fi
# the task path may be different under the restraint harness if the task
# is fetched directly from git, so use a relative path to the include task
ABS_DIR=$(dirname ${BASH_SOURCE[0]})"/patches"
echo "Absolute directory of ltp include patches: $ABS_DIR"  | tee -a $OUTPUTFILE

export TARGET_DIR="/mnt/testarea/ltp"
export TARGET="ltp-full-${TESTVERSION}"

SYSENV=$(uname -m)
ARCH=$SYSENV
export KVER=$(uname -r | cut -d'-' -f 1)
export KREV=$(uname -r | cut -d'-' -f 2 | cut -d'.' -f 1)
export KREV2=$(uname -r | cut -d'-' -f 2 | cut -d'.' -f 2)

# Whether NXBIT is Set in /proc/cpuinfo
export NXBIT=$(grep '^flags' /proc/cpuinfo 2>/dev/null | grep -q " nx " && echo TRUE || echo FALSE)
NR_CPUS=$(getconf _NPROCESSORS_ONLN || echo 1)

export MAKE="make -j${NR_CPUS}"

# Set unique log file.
OUTPUTDIR=/mnt/testarea
if ! [ -d $OUTPUTDIR ]; then
	echo "Creating $OUTPUTDIR"
	mkdir -p $OUTPUTDIR
fi
LTPDIR=$OUTPUTDIR/ltp
export OPTS=""

# Helper functions

# control where to log debug messages to:
# devnull = 1 : log to /dev/null
# devnull = 0 : log to file specified in ${DEBUGLOG}
export devnull=0

# Create debug log.
export DEBUGLOG=`mktemp -p /mnt/testarea -t DeBug.XXXXXX`
export SYSINFO=`mktemp -p /mnt/testarea -t SysInfo.XXXXXX`

# locking to avoid races
export lck=$OUTPUTDIR/$(basename $0).lck

if [ -z ${ARCH} ]; then
	ARCH=$(uname -m)
fi
