#!/bin/bash
# This file is used for RT related tests configurations.

do_bpf_config()
{
    # bz1969582 - the bpf:test_progs tests hit an expected mmap_zero avc
    # denial, unless we first turn mmap_low_allowed on
    echo "=== Setting mmap_low_allowed on ===" | tee -a $OUTPUTFILE
    setsebool -P mmap_low_allowed on
}

do_bpf_reset()
{
    # after testing completes, turn mmap_low_allowed off again
    echo "=== Setting mmap_low_allowed off ===" | tee -a $OUTPUTFILE
    setsebool -P mmap_low_allowed off
}
