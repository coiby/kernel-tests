#!/bin/bash

# Source Kdump tests common functions.
. ../include/runtest.sh

CheckCrashManpage()
{
    PrepareCrash

    # check command manpage output of this session.
    cat <<EOF >"crash_manpage_list.txt"
\*
alias
ascii
bt
btop
dev
dis
eval
exit
extend
files
mod
union
foreach
mount
search
vm
fuser
net
set
vtop
gdb
p
sig
waitq
help
ps
struct
whatis
ipcs
pte
swap
wr
irq
ptob
sym
q
kmem
ptov
sys
list
rd
task
log
repeat
timer
mach
runq
tree
EOF


    # Bug 2073412 - [RHEL 9 Beta] The "bpf" command information is missing in the man page of the crash utility
    # This issue was fixed in RHEL-9.1.0.
    # if not fixed,it has no 'bpf' command information in the crash utility man page.
    if $IS_RHEL9;then
        CheckSkipTest crash 8.0.1-2 checkonly || {
        cat <<EOF >> "crash_manpage_list.txt"
sbitmapq
bpf
EOF
        }
    fi

    # bug 1901738 - support 'sbitmapq' from RHEL8.7.
    if $IS_RHEL8;then
        CheckSkipTest crash 7.3.2-2 checkonly || {
        cat <<EOF >> "crash_manpage_list.txt"
sbitmapq
bpf
EOF
        }
    fi

    RhtsSubmit "$(pwd)/crash_manpage_list.txt"

    # print crash manpage content
    LogRun "man crash  > crash_manpage.log"
    RhtsSubmit "$(pwd)/crash_manpage.log"

    for i in $(cat crash_manpage_list.txt)
    do
        sed -n '/COMMANDS/,/FILE/p' crash_manpage.log |grep -q -E "\s{7}($i$|$i\s)" || {
        Error "It does not print $i manpage."
        }

    done
}

# --- start ---
Multihost CheckCrashManpage
