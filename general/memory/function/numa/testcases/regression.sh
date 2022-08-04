#!/bin/bash
set -x

let ret=0

case $(uname -m) in
    x86_64)
        if [ $(grep -c kernelpagesize_kB=4 /proc/self/numa_maps) -le 0 ]; then
            exit 1
        fi
        ;;
    ppc64|ppc64le)
        if [ $(grep -c kernelpagesize_kB=64 /proc/self/numa_maps) -le 0 ]; then
            exit 1
        fi
        ;;
esac

exit 0
