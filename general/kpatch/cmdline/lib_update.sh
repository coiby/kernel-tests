#! /bin/bash
# Parse kpatch patch nvr to support update of kpatch-patch.
# This uses the code from Job submitter.
function process_kpatch_patch_nvr() {
    local KPATCH_PACKAGE_VERSION=$1
    test -z "$KPATCH_PACKAGE_VERSION" && return
    local arch=$(uname -m)

    local KPATCH_NAME=$(echo $KPATCH_PACKAGE_VERSION | cut -d- -f1,2,3,4)
    local KPATCH_VERSION=$(echo $KPATCH_PACKAGE_VERSION | cut -d- -f5)
    local KPATCH_RELEASE=$(echo $KPATCH_PACKAGE_VERSION | cut -d- -f6)
    local KPATCH_KMOD_NAME=$(echo kpatch_${KPATCH_NAME//kpatch-patch-}-${KPATCH_VERSION}-${KPATCH_RELEASE//.el*} | sed 's/\.\|-/_/g')
    local KPATCH_URL_ROOT=${KPATCH_URL_ROOT:-}
    local kpatch_patch_srcbase=${kpatch_patch_base:-${KPATCH_URL_ROOT}/${KPATCH_NAME}/${KPATCH_VERSION}/${KPATCH_RELEASE}/src}
    local kpatch_patch_rpmbase=${kpatch_patch_base:-${KPATCH_URL_ROOT}/${KPATCH_NAME}/${KPATCH_VERSION}/${KPATCH_RELEASE}/$arch}
    local kpatch_kernel_vr=$(echo $KPATCH_NAME | cut -d- -f3- | sed 's/_/\./g').${KPATCH_RELEASE##*.}
    local MOD=${KPATCH_KMOD_NAME}
    local PATCHRPM=${KPATCH_PACKAGE_VERSION}.${arch}.rpm
    local PATCHSRPM=$kpatch_patch_srcbase/${KPATCH_PACKAGE_VERSION}.src.rpm
    local PATCHURL=$kpatch_patch_rpmbase/${PATCHRPM}

    # For kpatch-patch-3_10_0-327_59_2-1-1.el7 , release number is 1.
    # if release number is greater than 1, that means there was kpatch-patch
    # for the kernel was released before, in such case, we can do a upgrate
    # test, which can cover some kpatch-patch core code, so is the function
    # consistency issue(different versions of functions exist together.
    # (origin func a(), a'() in last patch, a''() in latest patch)
    local release_number=$(echo $KPATCH_RELEASE | cut -d . -f1)
    local release_end_str=$(echo $KPATCH_RELEASE | cut -d . -f2)
    while ((release_number > 1)); do
        KPATCH_UPDATE_BASE+=("${kpatch_patch_base:-${KPATCH_URL_ROOT}/${KPATCH_NAME}/${KPATCH_VERSION}/$((release_number -1)).${release_end_str}/${arch}}")
        KPATCH_UPDATE_PACKAGE+=("${KPATCH_NAME}-${KPATCH_VERSION}-${release_number}.${release_end_str}")
        KPATCH_UPDATE_RPM+=("${KPATCH_UPDATE_PACKAGE}.${arch}.rpm")
        ((release_number--))
    done
}

