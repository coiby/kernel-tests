#!/bin/bash
. /usr/share/beakerlib/beakerlib.sh             || exit 1

function cleanup()
{
	sed -i '/historical-service-time/d' /etc/multipath.conf
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

echo "configure multipath to use the historical-service-time selector"
sed -i '/^defaults/a \    path_selector "historical-service-time 0"' /etc/multipath.conf
rlRun "cat /etc/multipath.conf"
rlRun "service multipathd reload"
historical_service_time=$(multipath -l 2>&1 | grep -E 'historical-service-time 2')


if [ -n "$historical_service_time" ];then
	rlPass "------- PASS, Multipath now correctly parses the status of multipath devices that use the historical-service-time path selector. -------"
	cleanup
else
	rlFail "------- FAIL, Multipath wasn't correctly parsing the status output for multipath devices using the historical-service-time path selector --------"
	cleanup
fi
}

rlJournalStart
	rlPhaseStartTest
		run_test
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
