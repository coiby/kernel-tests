#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function kirk_runltp()
{
	RUNTEST=$1
	OUTPUTDIR=$2
	OPTIONS=$3

	LTPDIR=$OUTPUTDIR/ltp
	KIRKDIR=$OUTPUTDIR/kirk

	local thisdir=$(dirname $(readlink -f "${BASH_SOURCE[0]}"))
	local json2logs=$thisdir/json2logs.py
	local json2html=$KIRKDIR/utils/json2html.py

	# there is no way to disable kirk suite-timeout, to make sure we rely only on tmt/restraint timeout we set a very large (12h) number here
	time -p ${KIRKDIR}/kirk --framework ltp:root=${LTPDIR} --run-suite $RUNTEST -v --json-report $OUTPUTDIR/$RUNTEST.json --suite-timeout 43200 $OPTIONS | sed -r 's/\x1b\[[0-9;]*m//g'
	# Export KIRK_DEBUG so it's available in run.sh
	# shellcheck disable=SC2034
	export KIRK_DEBUG=$(find /tmp/kirk.$(whoami) -name debug.log -type f -exec stat --format '%W %n' {} + | sort -n | awk '{print $2}' | tail -1)
	if ! [ -e $OUTPUTDIR/$RUNTEST.json ]; then
		echo "FAIL:  $OUTPUTDIR/$RUNTEST.json not found"
		return 1
	fi
	python3 $json2logs --resfile $OUTPUTDIR/$RUNTEST.json --sumfile $OUTPUTDIR/$RUNTEST.log --runfile $OUTPUTDIR/$RUNTEST.run.log --failfile $OUTPUTDIR/$RUNTEST.fail.log
	python3 $json2html -r $OUTPUTDIR/$RUNTEST.json > $OUTPUTDIR/$RUNTEST.html
}
