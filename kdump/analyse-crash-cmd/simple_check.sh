#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

SimpleCheck()
{
    # Check the existence of the vmcore file.
    GetCorePath
}

#+---------------------------+
# $1 is the test phase name
Multihost "SimpleCheck" "simple_check"
