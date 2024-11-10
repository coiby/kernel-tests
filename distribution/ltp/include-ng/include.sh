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

function determine_test_version()
{
	if rlIsRHEL 6; then
		echo "20200120"
	elif rlIsRHEL 7; then
		# NOTE: don't forget to update ltp version on dci/rhel7.xml as well
		echo "20210927"
	elif rlIsRHEL 8 && rlIsRHEL '<=8.2'; then
		# NOTE: rhel82z build failed on newer ltp, fix to 20230929
		echo "20230929"
	elif rlIsRHEL 8 || rlIsRHEL '<=9.4'; then
		# NOTE: don't forget to update ltp version on dci/rhel8.xml as well
		echo "20240129"
	elif rlIsRHEL '9.5'; then
		echo "20240524"
	else
		echo "20240930"
	fi
}

TESTVERSION=${TEST_VERSION:-$(determine_test_version)}

if ! [[ "${TESTVERSION}" =~ ^[0-9]+$ ]]; then
	echo "ERROR: TESTVERSION (${TESTVERSION}) is not a valid number."
	exit 1
fi

if [ "${TESTVERSION}" -ge 20240930 ] || [ -n "${LTP_COMMIT_ID}" ]; then
	. "$CDIR"/../include-ng/defs.sh			|| exit 1
	. "$CDIR"/../include-ng/patch.sh		|| exit 1
	. "$CDIR"/../include-ng/build.sh		|| exit 1
	. "$CDIR"/../include-ng/utils.sh		|| exit 1
	. "$CDIR"/../include-ng/run.sh			|| exit 1
	. "$CDIR"/../include-ng/knownissue.sh		|| exit 1
else
	. "$CDIR"/../include/ltp-make.sh		|| exit 1
	. "$CDIR"/../include/runtest.sh			|| exit 1
	. "$CDIR"/../include/knownissue.sh		|| exit 1
fi
