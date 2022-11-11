#!/bin/bash
#Author Erik Hamera
#licence GNU GPL


if [ -z "$1" -o "$1" = "-h"  -o "$1" = "--help" ]; then
        echo "Usage examples:"
        echo "test_dispatch.sh default_test _ RHEL7 test_for_rhel7.sh _ RHEL8 test_for_rhel_8 _ FEDORA30 test_for_fedora_30"
        echo "test_dispatch.sh DEFAULT default_test parameters _ RHEL7 test_for_rhel7.sh parameters _ RHEL8 test_for_rhel_8 parameters"
        echo "RHEL7 test_for_rhel7.sh _ RHEL8 test_for_rhel_8 _ FEDORA30 test_for_fedora_30"
        exit 0
fi

tests="$(echo "$@" | sed 's/ _ /\n/g; s/ _$//')"

if [ "$2" = "_" -o -z "$2" ]; then
        # we have a default
        default="$1"
        shift
        shift
else
        if [ "$1" = "DEFAULT" ]; then
                default="$(echo "$tests" | grep "^DEFAULT" | head -n 1 | sed "s/^DEFAULT //")"
        else
                default=""
        fi
fi

select_test() {
        # $1: key/pointer to test (what string describes the test)
        # $tests: list of pairs "key test" separated by newline
        # $default: test to run if none is selected

        test="$(echo "$tests" | grep "^$1" | head -n 1 | sed "s/^$1 //")"
        if [ -z "$test" ]; then
                if [ "$default" ]; then
                        test="$default"
                else
                        test="false"
                fi
        fi
        echo "$test"
}

if grep -q '^Red Hat Enterprise Linux release 9\.' /etc/redhat-release; then
        #Prepare system for tests and run tests for RHEL 9

        if ! [ "$(rpm -qa python2)" ]; then
                dnf -y install python2
        fi
        if ! [ -L /usr/bin/python ]; then
                ln -s /usr/bin/python2 /usr/bin/python
        fi

        echo -n "Running: "
        select_test RHEL9
        eval "$test"
        exit "$?"
fi

if grep -q '^Red Hat Enterprise Linux release 8\.' /etc/redhat-release; then
        #Prepare system for tests and run tests for RHEL 8

        if ! [ "$(rpm -qa python2)" ]; then
                dnf -y install python2
        fi
        if ! [ -L /usr/bin/python ]; then
                ln -s /usr/bin/python2 /usr/bin/python
        fi

        echo -n "Running: "
        select_test RHEL8
        eval "$test"
        exit "$?"
fi

if grep -q '^Red Hat Enterprise Linux Server release 7\.' /etc/redhat-release; then
        #Prepare system for tests and run tests for RHEL 7

        echo -n "Running: "
        select_test RHEL7
        eval "$test"
        exit "$?"
fi

if grep -q '^Red Hat Enterprise Linux Server release 6\.' /etc/redhat-release; then
        #Prepare system for tests and run tests for RHEL 6

        echo -n "Running: "
        select_test RHEL6
        eval "$test"
        exit "$?"
fi

if grep -q '^Fedora release ' /etc/redhat-release; then
        #Prepare system for tests and run tests for Fedora 30

        echo -n "Running: "
        select_test FEDORA
        eval "$test"
        exit "$?"
fi

#if there is default, run tests on unknown system
if [ "$default" ]; then
        echo "Running: default"
        test="$default"
        eval "$test"
        exit "$?"
else
        exit "1"
fi

