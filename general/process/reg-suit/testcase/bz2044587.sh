#!/bin/bash
function bz2044587()
{
	rlIsRHEL ">=8.6" || { report_result ${FUNCNAME}_skip; return; }
	test -d ${FUNCNAME} || mkdir ${FUNCNAME}
	cp -f $DIR_SOURCE/${FUNCNAME}.cpp ./${FUNCNAME}/
	pushd ${FUNCNAME}

	rpm -q qt5-qtbase-devel || yum -y install qt5-qtbase-devel
	qmake-qt5 -project
	qmake-qt5
	rlRun "make" || return
	rlRun "test -f ${FUNCNAME}" || return

	rlRun "timeout 3 ./${FUNCNAME} /dev/urandom output" 0-255
	ls -l output

	local cmp_res="$(echo $(ls output -l | awk '{print $5}') \> 65536 | bc)"
	echo cmp_res=$cmp_res
	rlRun "[ "$cmp_res" = 1 ]"
	popd
	rm -fr ${FUNCNAME}
}
