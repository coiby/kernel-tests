#! /usr/bin/env sh

export PYTHONPATH=/mnt/tests/kernel/test-framework:/mnt/tests/kernel/audio_tests:$PYTHONPATH

test_name=$1
test_string=$2

if [ -f /usr/lib/beakerlib/beakerlib.sh ]
then
    source /usr/lib/beakerlib/beakerlib.sh
elif [ -f /usr/share/beakerlib/beakerlib.sh ]
then
    source /usr/share/beakerlib/beakerlib.sh
fi

if stat /run/ostree-booted > /dev/null 2>&1; then
        YUM="rpm-ostree -A --idempotent --allow-inactive install"
else
    if [ -x /usr/bin/dnf ]; then
        YUM="/usr/bin/dnf install -y"
    else
        YUM="/usr/bin/yum install -y"
    fi
fi

if rlIsRHEL
then
    if rlIsRHEL ">=8"
    then
        $YUM python3
        /usr/bin/env python3 $test_string
    else
        $YUM python2
        /usr/bin/env python2 $test_string
    fi
elif rlIsFedora
then
    if rlIsFedora ">=26"
    then
        $YUM python3
        /usr/bin/env python3 $test_string
    else
        $YUM python2
        /usr/bin/env python2 $test_string
    fi
elif rlIsCentOS
then
    if rlIsCentOS ">=8"
    then
        $YUM python3
        /usr/bin/env python3 $test_string
    else
        $YUM python2
        /usr/bin/env python2 $test_string
    fi
else
    echo "Unable to determine the OS"
    exit 1
fi