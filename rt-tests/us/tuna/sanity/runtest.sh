#!/bin/bash

# Source rt common functions
. ../../../include/lib.sh || exit 1

function tuna_rhel()
{
    # Reviewing the system in the CLI
    oneliner "tuna show_threads"
    oneliner "tuna show_irqs"

    # CPU tuning in the CLI
    oneliner "tuna run 'ps all' --cpus=0,1"

    # Task tuning in the CLI
    oneliner "tuna show_threads --threads=1"

    # New option cpu_power in the CLI since 10.2
    if rhel_in_range 10.2 99; then
        oneliner "tuna cpu_power -i"
        oneliner "tuna cpu_power -i -c 1"
    fi
}

function tuna_rhel8()
{
    # Reviewing the system in the CLI
    oneliner "tuna --show_threads"
    oneliner "tuna --show_irqs"

    # CPU tuning in the CLI
    oneliner "tuna --cpus=0,1 --run='ps all'"

    # Task tuning in the CLI
    oneliner "tuna --threads=1 --show_threads"
}

function runtest()
{
    oneliner "yum install -y tuna"
    # since 9.2 tuna CLI feature changes, detail in bz2062865
    if rhel_in_range 0 9.1; then
        tuna_rhel8
    else
        tuna_rhel
    fi
}

runtest
exit 0
