#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function kirk_run()
{
	RUNTEST=$1
	OUTPUTDIR=$2
	OPTIONS=$3

	LTPDIR=$OUTPUTDIR/ltp
	KIRKDIR=$OUTPUTDIR/kirk

	local thisdir=$(dirname $(readlink -f "${BASH_SOURCE[0]}"))
	local kirk_results=$thisdir/kirk_results.py

	time -p ${KIRKDIR}/kirk -f ltp:root=${LTPDIR} -r $RUNTEST -v -j $OUTPUTDIR/$RUNTEST.json --suite-timeout 10800 $OPTIONS | sed -r 's/\x1b\[[0-9;]*m//g'
	python3 $kirk_results --resfile $OUTPUTDIR/$RUNTEST.json --sumfile $OUTPUTDIR/$RUNTEST.log --runfile $OUTPUTDIR/$RUNTEST.run.log --failfile $OUTPUTDIR/$RUNTEST.fail.log
	# shellcheck disable=SC2034
	KIRK_DEBUG=$(find /tmp/kirk.$(whoami) -name debug.log -type f -exec stat --format '%W %n' {} + | sort -n | awk '{print $2}' | tail -1)
}
