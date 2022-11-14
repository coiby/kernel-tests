#!/bin/bash
if ! lsmod | grep 'intel_powerclamp' > /dev/null; then
        modprobe intel_powerclamp
fi
if ! lsmod | grep 'intel_rapl' > /dev/null; then
        modprobe intel_rapl
fi
