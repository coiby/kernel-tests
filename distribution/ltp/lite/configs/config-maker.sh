#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#   Signed-off-by: Li Wang <liwang@redhat.com>
#   SPDX-License-Identifier: GPL-3.0-or-later
#
#   Usage: LTP_VERSION=next ./config-maker.sh
#          LTP_VERSION=20220527 ./config-maker.sh
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# This script is using for RHELKT1LITE.${LTP_VERSION} generating
# Test in CONFIGFILE will be handled one by one according to their prefix
#  '%' - test will be kicked-out
#  '?' - test will be tweaked
#  '@' - test will be added-in

RHELKT1LITE=${RHELKT1LITE:-RHELKT1LITE}
CONFIGFILE=${CONFIGFILE:-CONFIGFILE}
LTP_VERSION=${LTP_VERSION:-20250530}
SOURCEDIR=$PWD
DOWNLOAD=${DOWNLOAD:-https://github.com/linux-test-project/ltp}

function rhelkt1lite_preparing()
{
	if [ $LTP_VERSION == "next" ]; then
		if [ ${LTP_COMMIT_ID} == "latest" ]; then
			wget ${DOWNLOAD}/archive/refs/heads/master.zip -O ltp.zip || exit 1
		else
			wget ${DOWNLOAD}/archive/${LTP_COMMIT_ID}.zip -O ltp.zip || exit 1
		unzip ltp.zip && mv ltp-*/ ltp-full-next/
		fi
	fi

	[ $LTP_VERSION != "next" ] && [ ! -f ltp-full-${LTP_VERSION}.tar.bz2 ] && \
		wget ${DOWNLOAD}/releases/download/${LTP_VERSION}/ltp-full-${LTP_VERSION}.tar.bz2 && \
		tar xjf ltp-full-${LTP_VERSION}.tar.bz2

	[ -d $SOURCEDIR/ltp-full-${LTP_VERSION}/ ] && \
		pushd $SOURCEDIR/ltp-full-${LTP_VERSION}/runtest/ >/dev/null;
		cat kernel_misc math ltp-aiodio.part3 ipc syscalls mm sched nptl pty tracing fs > $SOURCEDIR/$RHELKT1LITE.${LTP_VERSION}
		popd >/dev/null;

	rm -fr $SOURCEDIR/ltp-full-* $SOURCEDIR/ltp.zip
}

function block_issue_kickout()
{
	while read tst_case; do
		read -a cname <<<${tst_case#%}
		[ -n "${cname[0]}" ] && \
			sed -i "/^${cname[0]}/d" $SOURCEDIR/$RHELKT1LITE.${LTP_VERSION}
	done
}

function tweak_issue_hacking()
{
	while read tst_case; do
		read -a cname <<<${tst_case#?}
		[ -n "${cname[0]}" ] && \
			sed -i "s/^${cname[0]}\b.*$/${tst_case#?}/" $SOURCEDIR/$RHELKT1LITE.${LTP_VERSION}
	done
}

function aiodio_issue_adding()
{
	while read tst_case; do
		echo ${tst_case#@}
	done >> $SOURCEDIR/$RHELKT1LITE.${LTP_VERSION}
}

[ -f $SOURCEDIR/$CONFIGFILE ] && {
	rhelkt1lite_preparing

	grep "^%" $SOURCEDIR/$CONFIGFILE | block_issue_kickout

	grep "^?" $SOURCEDIR/$CONFIGFILE | tweak_issue_hacking

	grep "^@" $SOURCEDIR/$CONFIGFILE | aiodio_issue_adding
}

[ -f $SOURCEDIR/$RHELKT1LITE.${LTP_VERSION} ] && echo "Lucky: $RHELKT1LITE.${LTP_VERSION} has been generated!"
