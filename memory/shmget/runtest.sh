#!/bin/bash

# Assume the test will fail.
result=FAIL

# Helper functions
function CheckMemory ()
{
	memttl=$(free -b -t | grep Total: | awk -F: '{print $2}' | awk '{print $3}')
	if [ $memttl -lt $segment_size ]; then
	echo "***** Not enough memory to run test = $segment_size *****"
	rstrnt-report-result Test_skipped WARN 99
	exit 0
	fi
}

function TestHeader ()
{
	echo "*************************************"
	echo "***** Starting bz230658 (shmget) runtest.sh script *****"
	echo "***** Current Running Kernel Package = $kernbase *****"
	echo "***** Current Running Distro = $installeddistro *****"
	echo "*************************************"
}

# ---------- Start Test -------------
if grep 'release 10\.' /etc/redhat-release; then
	# https://issues.redhat.com/browse/RHELBU-1937
	rstrnt-report-result "32bit unsupported on el10" SKIP 0
	exit 0
fi

uname -m|grep x86_64
ret1=$?
uname -m|grep s390x && [ "$(echo $(grep -Eo "[0-9]+.[0-9]" /etc/redhat-release) \< 8.0 | bc)" = 1 ]
ret2=$?

if [ $ret1 -ne 0 ] && [ $ret2 -ne 0 ]; then
	rstrnt-report-result Test_Skipped PASS 99
	exit 0
fi

if [ $ret2 -eq 0 ];  then
	echo "Building for s390x environment"
	gcc -o tshmget -m31 tshmget.c
else
	gcc -o tshmget -m32 tshmget.c
fi


# Setup some variables
if [ -e /etc/redhat-release ] ; then
	installeddistro=$(cat /etc/redhat-release)
else
	installeddistro=unknown
fi

kernbase=$(rpm -q --queryformat '%{name}-%{version}-%{release}.%{arch}\n' -qf /boot/config-$(uname -r))

TestHeader

# This value is 1 byte more than 2GB
segment_size=2147483649

CheckMemory

echo "Attempting to set shmmax to $segment_size..."
echo $segment_size > /proc/sys/kernel/shmmax
echo -n "Contents of /proc/sys/kernel/shmmax now "
cat /proc/sys/kernel/shmmax
echo

basearch=$(uname -m)
echo "Making sure needed 32-bit deps are installed..."
case $basearch in
	x86_64*)
		yum -y install glibc-devel.i386 libgcc.i386
		# for rhel6 and later
		yum -y install glibc-devel.i686 libgcc.i686
		;;
	s390x*)
		yum -y install glibc-devel.s390 libgcc.s390
		;;
	*)
		echo "This test is for x86_64 and s390x only..."
		;;
esac
echo
echo "Making sure the test app is actually built..."

./tshmget $segment_size
if [ "$?" -eq "0" ]; then
	export result=PASS
else
	export result=FAIL
fi

echo "Test result: $result"

rstrnt-report-result $TEST $result 100

exit 0
