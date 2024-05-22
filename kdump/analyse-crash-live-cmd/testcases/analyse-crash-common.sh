#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

analyse()
{
    # Check command output of this session.

    cat <<EOF >"${K_TESTAREA}/crash.cmd"
files
files -c 1
mod
mod -S
mod -s twofish
runq
alias
foreach bt
foreach crash task
foreach files
mount
search -u deadbeef
search -s _etext -m ffff0000 abcd
search -p babe0000 -m ffff
vm
vm -p 1
ascii
fuser /
net
set
set -p
set -v
bt
bt -t
bt -r
bt -T
bt -l 1
bt -f 1
bt -e
bt -E
bt 0
gdb help
p init_mm
sig -l
btop 512a000
help help
ps
ps -k
ps -u
ps -s
struct vm_area_struct
whatis linux_binfmt
dev
dev -i
dev -d
dev -D
pte d8e067
swap
dis sys_signal
kmem -i
sym -q pipe
ptob 512a
eval (1 << 32)
ptov 56e000
sys config
sys -c
sys -c select
rd jiffies
task
extend
mach
timer
EOF

    # Only test -k option for 32-bit systems.
    #
    # The -k command option has become fairly useless on 64-bit
    # machines, because *all* of physical memory can be considered
    # "kernel" memory because all of memory can be unity-mapped.  (On
    # 32-bit systems, only the low 896MB of physical memory can be
    # unity-mapped) So in practical usage, a user would restrict the
    # starting and ending addresses with -s and -e. On large systems,
    # it's also extremely time-consuming, and again, with very little
    # benefit. -- Dave Anderson
    #
    if [ "${K_ARCH}" = 'i686' ]; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
search -k deadbeef
EOF
    fi

    # remove 'irq' command from s390x (bug 1204584)
    if [ "$(uname -m)" != "s390x" ]; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
irq
EOF
    fi

    # remove 'pte d8e067' from ppc64le (bug 1447172)
    if [ "$(uname -m)" = "ppc64le" ]; then
        sed -i /"pte d8e067"/d "${K_TESTAREA}/crash.cmd"
    fi


# RHEL5/6/7 takes different version of crash utility respectively, so
# in here add the cmds specific to each version.

    # On RHEL5/6, following commands are not supported
    # file -c #bz1673285
    # dev -D  #bz1662039
    if ( $IS_RHEL5 || $IS_RHEL6 ); then
        sed -i /"files -c"/d "${K_TESTAREA}/crash.cmd"
        sed -i /"dev -D"/d "${K_TESTAREA}/crash.cmd"
    fi


    if $IS_RHEL5; then
        # This command is not applicable to Xen, because
        # CONFIG_X86_NO_IDT=y.
        if [ "${K_KVARI}" != 'xen' ]; then
            echo "irq -d" >>"${K_TESTAREA}/crash.cmd"
        fi

        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
mount -i
dev -p
list -s module.version -H modules
EOF
    fi

    if $IS_RHEL6; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
list -o task_struct.tasks -h init_task
EOF
    fi

    if ( $IS_RHEL7 || $IS_RHEL8 || $IS_RHEL9 ); then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
list -o task_struct.tasks -h init_task
EOF
    fi

    # bz1662039: dev -p is supported on RHEL8 except s390x
    if $IS_RHEL8 && [ "$(uname -m)" != "s390x" ]; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
dev -p
EOF
    fi

    # 'mount -f' - only supported on kernels prior to Linux 3.13.
    if [ "${RELEASE}" -lt 8 ]; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
mount -f
EOF
    fi

    # 'mach -m' - Display the physical memory map (x86, x86_64 and ia64 only).
    if [ "${K_ARCH}" = 'x86_64' ]; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
mach -m
EOF
    fi

    cat <<EOF >> "${K_TESTAREA}/crash.cmd"
exit
EOF

    # https://bugzilla.redhat.com/show_bug.cgi?id=1338579
    # "kmem:.*slab.*invalid freepointer" is not a bug on live system
    export SKIP_ERROR_PAT="kmem:.*error.*encountered\|kmem:.*slab.*invalid freepointer.*"

    CrashCommand "" "" "" "crash.cmd"
    export SKIP_ERROR_PAT=
    rm -rf "${K_TESTAREA}/crash.cmd"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" analyse
