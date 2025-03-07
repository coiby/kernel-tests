#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest (){

	tok yum -y install kernel-devel
	pushd mcsafe_test
	tlog "INFO: will compile mcsafe_test module"
	tok make

	for i in `seq 0 500`
	do
		tlog "INFO: start mcsafe_test with byteoffset:$i"
		tok "./TEST $i"
	done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
