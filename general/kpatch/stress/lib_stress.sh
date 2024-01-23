#!/bin/bash

# Stressers for the kpatch load

STRESS_FACTOR=${STRESS_FACTOR:-1}
BUILDS_URL="${BUILDS_URL:-}"
LOOP_TIME_DEFAULT=100
NR_CPU=$(grep -wo processor /proc/cpuinfo | wc -l)

# We can start ((NR_CPU * STRESS_FACTOR)) threads in kbuild stress.
NR_CPU=$((STRESS_FACTOR * NR_CPU))

karch=$(uname -m)
kver=$(uname -r | cut -f1 -d'-')
krel=$(uname -r | cut -f2 -d'-' | sed -e "s/\.$karch$//" -e "s/\.$karch+debug$//" -e "s/\.$karch.debug$//")

STRESSER_FILE="stresser"
STRESSER_PATH="$(pwd)"

trap cleanup EXIT

function cleanup()
{
    local stresser=$(cat $STRESSER_PATH/$STRESSER_FILE)
    finish_$stresser
    test -f ERROR && rm -f ERROR
}


# Print message
function Error()
{
    touch ERROR
    echo "ERROR: $*" | tee ERROR
    exit 1
}

function Info()
{
    echo "INFO: $*"
}

# Kernel build stresser
function download_ksrc()
{
    which wget || yum -y install wget
    if [[ ! -e "kernel-${kver}-${krel}.src.rpm" ]]; then
        yumdownloader -q -y --source kernel-${kver}-${krel} \
            || wget ${BUILDS_URL}/kernel/${kver}/${krel}/src/kernel-${kver}-${krel}.src.rpm
    fi
    [ $? -ne 0 ] && Error "${kver}-${krel} srpm download failed"
}

function prep_kbuild()
{
    unset ARCH
    echo "kbuild" > $STRESSER_FILE
    local k_srpm=$(ls *.src.rpm)
    local k_spec=${HOME}/rpmbuild/SPECS/kernel.spec
    k_build=$(ls ${HOME}/rpmbuild/BUILD/kernel-${kver}-${krel}/linux-*/ | head -1)
    Info "srpm name is $k_srpm"
    rpm -ivh $k_srpm || Error "Install srpm $k_srpm failed"
    yum-builddep -y $k_spec || Error "build dependency can't be solved."
    rpmbuild -bp $k_spec
}

function start_kbuild()
{
    Info "Pushing dir to ... $k_build"
    pushd $k_build
    make olddefconfig || Error "Failed olddefconfig"
    make prepare modules_prepare || Error "Failed modules prepare"
    Info "Start compile kernel process with $NR_CPU processes"
    make -j ${NR_CPU} | tee build.log || Error "kbuild stress failed to start."
    make install modules_install -j ${NR_CPU} | tee -a build.log
}

function finish_kbuild()
{
    rm -fr $k_build
    Info "poping back to $CDIR"
    popd
}

function load_kbuild()
{
    local loop=${1:-20}
    download_ksrc
    Info "========== Kernel build stress =============="
    while ((loop--)); do
        prep_kbuild
        start_kbuild
        finish_kbuild
    done
}

# Stress-ng stresser
function prep_stress()
{
    echo "stress" > $STRESSER_FILE
    yum install -q -y stress-ng
}

function start_stress()
{
    local loop_orig=${1:-$LOOP_TIME_DEFAULT}
    local loop=${1:-$LOOP_TIME_DEFAULT}
    while ((loop--)); do
        lsmod > /dev/null
        stress-ng --cpu ${NR_CPU} --io ${NR_CPU} --vm ${NR_CPU} --timeout 10s
    done
    loop=$loop_orig
    while ((loop--)); do
        lsmod > /dev/null
        stress-ng --cpu ${NR_CPU} --io ${NR_CPU} --hdd ${NR_CPU} --timeout 10s
    done
    loop=$loop_orig
    while ((loop--)); do
        lsmod > /dev/null
    done
}

function finish_stress()
{
    cat /proc/stat > /dev/null
}

function load_stress()
{
    Info "========== stress-ng stress =============="
    prep_stress
    local duraion=${1:-20}
    local end=$(( $(date +%s) + duraion ))
    local now=$(date +%s)
    while ((now < end)); do
        start_stress 1
        finish_stress
        now=$(date +%s)
    done
}

# Stresser four, perf bench, dummy here.
function prep_trace()
{
    echo "trace" > $STRESSER_FILE
    mount -t debugfs dbg /sys/kernel/debug/
    echo nop > /sys/kernel/debug/tracing/current_tracer
}

function finish_trace()
{
    echo nop > /sys/kernel/debug/tracing/current_tracer
    echo 0 > /sys/kernel/debug/tracing/events/enable
}

function start_trace()
{
    local loop_orig=${1:-$LOOP_TIME_DEFAULT}
    local loop=${1:-$LOOP_TIME_DEFAULT}
    echo 1 > /sys/kernel/debug/tracing/events/enable
    while ((loop--)); do
        echo function_graph > /sys/kernel/debug/tracing/current_tracer
        echo nop > /sys/kernel/debug/tracing/current_tracer
    done
    local loop=$loop_orig
    while ((loop--)); do
        echo function > /sys/kernel/debug/tracing/current_tracer
        echo nop > /sys/kernel/debug/tracing/current_tracer
    done
    local loop=$loop_orig
    while ((loop--)); do
        echo function > /sys/kernel/debug/tracing/current_tracer
        echo function_graph > /sys/kernel/debug/tracing/current_tracer
    done
}

function load_trace()
{
    Info "========== stress trace stress =============="
    prep_trace
    while :; do
        start_trace "$@"
        finish_trace
    done
}
