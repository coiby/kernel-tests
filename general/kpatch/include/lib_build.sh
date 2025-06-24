#!/bin/sh
. /usr/share/beakerlib/beakerlib.sh ||  exit 1

built_kpatch_patch=/home/kpatch-patch-modules
NFS_SHARE=${NFS_SHARE:-}
KPATCH_LOCATION=${KPATCH_LOCATION:-"/data/kpatch"}
KPATCH_SHARE="${NFS_SHARE}:${KPATCH_LOCATION}"
KPATCH_MNT="/mnt/kpatch"

function create_build_dir(){
    mkdir -p ${built_kpatch_patch}
}

function upload_modules() {
    #sleep 120s to wait the module_collector save all modules.
    sleep 120
    if [ ! -z "${NFS_SHARE}" ]; then
        if ! mount | grep ${KPATCH_MNT} > /dev/null; then
            echo -n "Mount ${KPATCH_SHARE} with kpatch modules"
            mkdir -p "${KPATCH_MNT}"
            mount -t nfs "${KPATCH_SHARE}" "${KPATCH_MNT}" || { echo "Mount FAIL." &&  return ; }
        fi
        mkdir -p "${KPATCH_MNT}/$(uname -r)"
        \cp -af ${built_kpatch_patch}/* "${KPATCH_MNT}/$(uname -r)/"
    fi
}

# use background worker to save already built modules
function start_module_collect_worker() {
    echo "Current workding dir is $(pwd)"
    ./module_collector.sh &
    module_collector=$!
}

function end_module_collect_worker() {
    kill $module_collector
}

# shellcheck disable=SC2034
function basic_build() {
    set -x
    cd kpatch && make all && BASIC_DONE=1 || exit 1
    cd ..
    set +x
}

function RunBuildTest() {
    local ret=0

    pushd kpatch
    mlog=kpatch-modules.log
    rlRun "make integration-slow KPATCH_BUILD_OPTS=\"${KPATCH_BUILD_OPTS}\" 2>&1"
    ret=$?
    [ ${ret} -ne 0 ] && echo "kpatch build test failed."
    find . -name "*.ko" | tee ${mlog}
    rlFileSubmit ${mlog}
    for file in test/integration/*.log; do
        mv ${file} ${file%.log}-slow.log
        rlFileSubmit "${file%.log}-slow.log"
    done
    popd
    upload_modules

    return ${ret}
}

function RunCombinedBuild() {
    local ret=0

    pushd kpatch
    rlRun "make integration-quick KPATCH_BUILD_OPTS=\"${KPATCH_BUILD_OPTS}\" 2>&1"
    ret=$?
    [ ${ret} -ne 0 ] && echo "kpatch combined build test failed."
    for file in test/integration/*.log; do
        mv ${file} ${file%.log}-quick.log
        rlFileSubmit "${file%.log}-quick.log"
    done
    popd
    upload_modules

    return ${ret}
}

function get_srpm_name() {
    kern="kernel-$(uname -r | sed 's/\.[^.]*$//')"
    echo "${kern}.src.rpm"
}

function get_src_rpm() {
    k_ver=$(uname -r | awk -F "-" '{print $1}')
    k_rel=$(uname -r | awk -F "-" '{print $2}' | sed 's/\.[^.]*$//')

    src_url=https://download.devel.redhat.com/brewroot/packages/kernel/"$k_ver"/"$k_rel"/src/$(get_srpm_name)
    wget "$src_url"

    return $?
}

function get_patch_file() {
    ucid=$1
    u_url="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/?id=$ucid"

    wget "$u_url" -O "$ucid".patch

    return $?
}

