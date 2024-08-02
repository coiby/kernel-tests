#!/bin/bash

TEST_LINK="test-link"
COMMON_PACKAGES="meson gcc check-devel valgrind doxygen cmake"
TIMEOUT=500
LIBEVDEV_REPO=https://gitlab.freedesktop.org/libevdev/libevdev

source /usr/share/beakerlib/beakerlib.sh || exit 1

function setupRepos
{
    rlRun "rm -rf libevdev"

    for package in $COMMON_PACKAGES; do
        echo "package name: $package"
        package_exist=$(rpm -qa | grep ^"$package"-)
        if [ -z "$package_exist" ]
        then
            rlLog "installing package $package"
            if stat /run/ostree-booted > /dev/null 2>&1
            then
                rlRun "rpm-ostree -A install $package"
            else
                rlRun "dnf install -y $package"
            fi
       fi
    done

    rlRun "git clone $LIBEVDEV_REPO"
    cd libevdev || { echo "cannot cd to libevdev directory"; exit 1; }
    rlRun "meson setup builddir"
    rlRun "meson compile -C builddir"

    TESTS_DIR=$(pwd)/builddir
    echo "test dir: $TESTS_DIR"
    rlLog "tests dir at $TESTS_DIR\n"
}

function setup
{
    rlPhaseStartSetup
    setupRepos
    rlPhaseEnd
}

function getTests
{
    cd "$TESTS_DIR" || { echo "cannot cd to tests directory"; exit 1; }
    ALL_TESTS=()
    files="$(ls -d test-*)"
    for file in $files; do
        if [[ $file != *.* ]]
        then
            ALL_TESTS+=("$file")
        fi
    done
}

function runtest
{
    rlPhaseStartTest
    cd "$TESTS_DIR" || { echo "cannot cd to tests directory"; exit 1; }
    getTests
    for test in "${ALL_TESTS[@]}"; do
        test_exec=$(CK_DEFAULT_TIMEOUT=$TIMEOUT ./"$test")
        test_res=$?
        if [ -n "$test_exec" ]
        then
            rlLog "$test_exec"
        fi

        if [ "$test" == "$TEST_LINK" ]
        then
            rlAssertGreater "Assert $test return code" $test_res 0
        else
            rlAssertEquals "Assert $test return code" $test_res 0
        fi
        rlLog "$test return value: $test_res\n"
    done
    rlPhaseEnd
}

function main
{
    rlJournalStart
    setup
    runtest
    rlJournalEnd
}

main
exit $?
