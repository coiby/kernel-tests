#!/bin/bash
function bz1660290()
{
	uname -r | grep -q s390x || { echo "only run in s390x, return" && return; }
	rlIsRHEL ">=8.4" || { echo "only run since 8.4 return" && return; }
	dbginfo.sh
	return 0;
}
