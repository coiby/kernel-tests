function bz1651416()
{
	if [[ "$(uname -m)" = "x86_64" ]]; then
		rlRun "tar xf $DIR_SOURCE/$FUNCNAME.tar"
		if rlIsRHEL '7'; then
			rlRun "testcase/source/${FUNCNAME}_rhel6"
			rlRun "testcase/source/${FUNCNAME}_rhel8"
		elif rlIsRHEL '8'; then
			rlRun "testcase/source/${FUNCNAME}_rhel6"
			rlRun "testcase/source/${FUNCNAME}_rhel7"
		fi
	fi
}
