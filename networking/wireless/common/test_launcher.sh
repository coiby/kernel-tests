#! /usr/bin/env sh

export PYTHONPATH=/mnt/tests/kernel/test-framework:/mnt/tests/kernel/wireless_tests:$PYTHONPATH

test_name=$1
test_string=$2

. /usr/bin/rhts-environment.sh
if [ -f /usr/lib/beakerlib/beakerlib.sh ]
then
    . /usr/lib/beakerlib/beakerlib.sh
elif [ -f /usr/share/beakerlib/beakerlib.sh ]
then
    . /usr/share/beakerlib/beakerlib.sh
fi

if rlIsRHEL
then
    if rlIsRHEL ">=8"
    then
        dnf -y install python3
        rhts-run-simple-test "$test_name" "/usr/bin/env python3 $test_string"
    else
        yum -y install python2
        rhts-run-simple-test "$test_name" "/usr/bin/env python2 $test_string"
    fi
elif rlIsFedora
then
    if rlIsFedora ">=26"
    then
        dnf -y install python3
        rhts-run-simple-test "$test_name" "/usr/bin/env python3 $test_string"
    else
        yum -y install python2
        rhts-run-simple-test "$test_name" "/usr/bin/env python2 $test_string"
    fi
elif rlIsCentOS
then
    if rlIsCentOS ">=8"
    then
        dnf -y install python3
        rhts-run-simple-test "$test_name" "/usr/bin/env python3 $test_string"
    else
        yum -y install python2
        rhts-run-simple-test "$test_name" "/usr/bin/env python2 $test_string"
    fi
else
    echo "Unable to determine the OS"
    exit 1
fi
