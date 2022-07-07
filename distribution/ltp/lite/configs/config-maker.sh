#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#   Signed-off-by: Li Wang <liwang@redhat.com>
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# This script is using for RHELKT1LITE.${LTP_VERSION} generating
# Test in CONFIGFILE will be handled one by one according to their prefix
#  '%' - test will be kicked-out
#  '?' - test will be tweaked
#  '@' - test will be added-in

LTP_VERSION=20220527
SOURCEDIR=$PWD
LOOKASIDE=${LOOKASIDE:-http://download.devel.redhat.com/qa/rhts/lookaside/}

function rhelkt1lite_preparing()
{
	[ -f ltp-full-${LTP_VERSION}.bz2 ] || \
		wget ${LOOKASIDE}/ltp-full-${LTP_VERSION}.bz2 && \
		tar xjf ltp-full-${LTP_VERSION}.bz2

	[ -d $SOURCEDIR/ltp-full-${LTP_VERSION}/ ] && \
		pushd $SOURCEDIR/ltp-full-${LTP_VERSION}/runtest/ >/dev/null;
		cat kernel_misc math fsx ipc syscalls mm sched nptl pty tracing fs > $SOURCEDIR/RHELKT1LITE.${LTP_VERSION}
		popd >/dev/null;

	rm -fr $SOURCEDIR/ltp-full-*
}

function block_issue_kickout()
{
	while read tst_case; do
		read -a cname <<<${tst_case#%}
		[ -n "${cname[0]}" ] && \
			sed -i "/^${cname[0]}/d" $SOURCEDIR/RHELKT1LITE.${LTP_VERSION}
	done
}

function tweak_issue_hacking()
{
	while read tst_case; do
		read -a cname <<<${tst_case#?}
		[ -n "${cname[0]}" ] && \
			sed -i "s/^${cname[0]}\b.*$/${tst_case#?}/" $SOURCEDIR/RHELKT1LITE.${LTP_VERSION}
	done
}

function aiodio_issue_adding()
{
	while read tst_case; do
		echo ${tst_case#@}
	done >> $SOURCEDIR/RHELKT1LITE.${LTP_VERSION}
}

[ -f $SOURCEDIR/CONFIGFILE ] && {
	rhelkt1lite_preparing

	grep "^%" $SOURCEDIR/CONFIGFILE | block_issue_kickout

	grep "^?" $SOURCEDIR/CONFIGFILE | tweak_issue_hacking

	grep "^@" $SOURCEDIR/CONFIGFILE | aiodio_issue_adding
}

[ -f $SOURCEDIR/RHELKT1LITE.${LTP_VERSION} ] && echo "Lucky: RHELKT1LITE.${LTP_VERSION} has been generated!"
