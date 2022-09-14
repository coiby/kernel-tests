#!/bin/bash
function bzmeminfo_check()
{
        cat /proc/meminfo
        rlRun "meminfo_check" -l
}
