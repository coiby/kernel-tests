#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

analyse()
{
    # Check command output of this session.
    # See BZ1203238: kmem -S -I kmalloc-8,kmalloc-16
    cat <<EOF >"${K_TESTAREA}/crash.cmd"
help -v
help -m
help -n
swap
mod
mod -S
runq
foreach bt
foreach files
mount
vm
net
search -u deadbeef
set
set -p
set -v
bt
bt -t
bt -r
bt -T
bt -l
bt -a
bt -f
bt -e
bt -E
bt -F
bt 0
ps
ps -k
ps -u
ps -s
dev
kmem -i
kmem -s
task
p jiffies
sym jiffies
rd -d jiffies
set -c 0
EOF

    # Remove "kmem -S -I kmalloc-8,kmalloc-16" from ppc64le tests.
    # It takes > 1 hour to run on a ppc64le machine with 16 cpus. and takes
    # > 3 hours to run on a ppc64le machine with 100+ cpus.
    if [ "$(uname -m)" != "ppc64le" ]; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
kmem -S -I kmalloc-8,kmalloc-16
EOF
fi

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

    # Bug 1204584, In order for the "irq -u" option to work, the architecture
    # must have either the "no_irq_chip" or the "nr_irq_type" symbols to exist.
    # The s390x has none of them:
    if [ "$(uname -m)" != "s390x" ]; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
irq
irq -b
irq -u
EOF
fi

    # RHEL4 need set the contest to the init task first, see Bug662550
    if expr "$FAMILY" : '[a-zA-Z]\+4'; then
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
set 1
EOF
fi

    # RHEL5/6/7 takes different version of crash utility respectively, so
    # in here add the cmds specific to each version.

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

    CheckVmlinux
    GetCorePath

    [ -f "${K_TESTAREA}/crash.vmcore.log" ] && rm -f "${K_TESTAREA}/crash.vmcore.log"
    # shellcheck disable=SC2154
    CrashCommand "" "${vmlinux}" "${vmcore}" "crash.cmd"
    rm -f "${K_TESTAREA}/crash.cmd"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" analyse
