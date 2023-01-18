#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh             || exit 1

function cleanup()
{
	sed -i '/foo/d' /etc/multipath.conf
	service multipathd stop
	multipath -F
	yum -y remove device-mapper-multipath
	return 0

}

function run_test()
{
yum -y install device-mapper-multipath
rpm -qa | grep multipath
mpathconf --enable
service multipathd restart

rlRun "man multipath.conf  2>&1 | grep -E 'verbosity'"
echo "set verbosity to 7"
rlRun "sed -i '/^defaults/a \    verbosity 7 ' /etc/multipath.conf"
verbosity=$(multipath -ll 2>&1 | grep -E 'value for verbosity too large, capping at 4')
echo "delete verbosity line to retore /etc/multipath.conf"
rlRun "sed -i '/verbosity/d' /etc/multipath.conf"
echo "set foo to 2"
rlRun "sed -i '/^defaults/a \    foo 2 ' /etc/multipath.conf"
rlRun "service multipathd reload"
foo=$(multipath -ll 2>&1 | grep -E 'invalid keyword in the defaults section: foo')


if [ -n "$verbosity" ] && [ -n "$foo" ];then
	rlPass "------- PASS, For numeric values with ranges, multipath.conf will now cap the values to the range. For values with keywords, multipath will now print a  message if the keyword is invalid. -------"
	cleanup
else
	rlFail "------- FAIL, multipath doesn't correctly print warning with invalid values --------"
	cleanup
fi
}

rlJournalStart
	rlPhaseStartTest
		run_test
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
