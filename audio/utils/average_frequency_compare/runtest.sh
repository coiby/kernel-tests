#!/bin/sh
export PYTHONPATH=../../../test-framework
source /usr/bin/rhts-environment.sh
if [ -f /usr/lib/beakerlib/beakerlib.sh ]
then
    source /usr/lib/beakerlib/beakerlib.sh
elif [ -f /usr/share/beakerlib/beakerlib.sh ]
then
    source /usr/share/beakerlib/beakerlib.sh
fi

# Install prerequisites

if rlIsRHEL
then
    if rlIsRHEL ">=8"
    then
        dnf -y install python3 python3-pip
        pip3 install scipy numpy
    else
        export preset="epel"
        make -C /mnt/tests/distribution/setup_repository run
        yum -y install python2 scipy
    fi
elif rlIsFedora
then
    if rlIsFedora ">=26"
    then
        dnf -y install python3 python3-scipy
    else
        yum -y install python2 python2-scipy
    fi
else
    echo "Unable to determine the OS"
    exit 1
fi

test_string="./average_frequency_compare.py"

# Check for TOLERANCE command line argument
if [ -n "${TOLERANCE+1}" ]
then test_string="$test_string --tolerance $TOLERANCE"
fi

# Check for TARGET_FREQUENCY command line argument
if [ -n "${TARGET_FREQUENCY+1}" ]
then test_string="$test_string --target-frequency $TARGET_FREQUENCY"
fi

# Check for COMPARE_FILES command line argument
if [ -n "${COMPARE_FILES+1}" ]
then
    files=(${COMPARE_FILES//,/ })
    for file in "${files[@]}"
    do
        test_string="$test_string --file $file"
    done
fi

# Go back to the test directory
echo $test_string

sh ../../../test-framework/test_launcher.sh $TEST "$test_string $@"
