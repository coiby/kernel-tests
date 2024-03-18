#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

source ../../../cki_lib/libcki.sh

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
YUM=$(cki_get_yum_tool)

function libnvme_setup
{
	pushd "$CDIR" || exit 1
	rlRun "$YUM download libnvme --source"
	typeset rpmfile=$(ls -1 libnvme*.src.rpm)
	rlAssertExists "$rpmfile"
	if (($? != 0)); then
		rlLog "Abort test as libnvme source rpm doesn't exists"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi
	rlRun "rpm -ivh $rpmfile"
	rlRun "rpmbuild -bp ~/rpmbuild/SPECS/libnvme.spec"
	libnvme_srcdir=$(realpath /root/rpmbuild/BUILD/libnvme-*)
	rlRun "pushd $libnvme_srcdir"
	rlRun "meson .build"
}

function startup
{
	if rlIsRHEL ">9.0" || rlIsFedora ||rlIsCentOS "9"; then
		libnvme_setup

	else
		rlLog "Abort test as $(cat /etc/redhat-release) doesn't support"
		rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
		rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
	fi
}

function runtest
{
	local ret=0
	rlRun "pushd $libnvme_srcdir"
	rlRun "cd .build"
	rlRun "meson test"
	ret=$?
	if (( ret != 0 )); then
		echo ">> There are failing tests, pls check it"
	fi
}

cki_main
