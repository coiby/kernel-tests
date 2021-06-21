#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source beaker environment
. ../../cki_lib/libcki.sh || exit 1

function rt_package_install()
{
    packages="rt-tests rt-setup rteval rteval-loads tuned-profiles-realtime tuna realtime-tests realtime-setup"
    echo "install needed package $packages " | tee -a $OUTPUTFILE
    for i in $packages; do
        if $(rpm -q --quiet $i); then
            continue
        else
            yum install -y $i
        fi
    done
}

function rt_env_setup()
{
    kernel_name=$(uname -r)
    if [[ $kernel_name =~ "rt" ]]; then
        echo "running the $kernel_name" | tee -a $OUTPUTFILE
        rt_package_install
    else
        echo "non rt kernel, please use rt kernel" | tee -a $OUTPUTFILE
        rstrnt-report-result $TEST SKIP
        exit
    fi
}
