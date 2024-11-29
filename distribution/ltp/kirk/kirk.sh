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

	time -p ${KIRKDIR}/kirk -f ltp:root=${LTPDIR} -r $RUNTEST -v -j $OUTPUTDIR/$RUNTEST.json $OPTIONS | sed -r 's/\x1b\[[0-9;]*m//g'
	python3 $kirk_results --resfile $OUTPUTDIR/$RUNTEST.json --sumfile $OUTPUTDIR/$RUNTEST.log --runfile $OUTPUTDIR/$RUNTEST.run.log --failfile $OUTPUTDIR/$RUNTEST.fail.log
}
