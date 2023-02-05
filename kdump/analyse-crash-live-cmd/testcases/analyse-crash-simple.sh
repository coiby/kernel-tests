#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

analyse()
{
    # Only check the return code of this session.
    #
    # From the maintainer, Dave Anderson.
    #
    #  foreach bt
    #  foreach files
    #
    # Any "foreach" command option should *expect* to fail given that the
    # underlying set of tasks are changing while the command is being run.
    #
    #  runq
    #
    # The runq will constantly be changing, so results are indeterminate.
    #
    #  kmem -i
    #  kmem -s
    #  kmem -S - The "kmem -S" test is invalid when run on a live system.
    #
    # The VM, and the slab subsystem specifically, is one of the most active
    # areas in the kernel, and so the commands above are very likely to run
    # into stale/changing pointers and such, and may fail as a result.

    cat <<EOF > "${K_TESTAREA}/crash-simple.cmd"
sym -l
log -m
runq
foreach bt
foreach files
kmem -i
kmem -s
exit
EOF

    # https://bugzilla.redhat.com/show_bug.cgi?id=1338579
    # "kmem:.*slab.*invalid freepointer" is not a bug on live system
    export SKIP_ERROR_PAT="kmem:.*error.*encountered\|kmem:.*slab.*invalid freepointer.*"

    CrashCommand "" "" "" "crash-simple.cmd"
    export SKIP_ERROR_PAT=
    rm -f "${K_TESTAREA}/crash-simple.cmd"
}

#+---------------------------+

MultihostStage "$(basename ${0%.*})" analyse 

