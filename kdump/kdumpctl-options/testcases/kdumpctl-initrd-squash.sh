#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# bz1896698 - [feat] Add kexec-tools initrd support for zstd compression

if [ "${RELEASE}" -lt 9 ] || CheckSkipTest kexec-tools 2.0.23-5; then
    Skip "Squash initrd feature is not supported."
    Report
fi

CheckSquashRoot()
{
    # 1.default (+squash):
    local confile="${KDUMP_CONFIG}.squashroot"
    cp -f ${KDUMP_CONFIG} ${confile}
    RhtsSubmit "${confile}"
    pushd /tmp
    Log "Current running: ${INITRD_KDUMP_IMG_PATH}"
    lsinitrd --unpack "${INITRD_KDUMP_IMG_PATH}" squash-root.img || {
        Error "Cannot unpack squash-root.img from kdump.img"
    }
    [ -f "/tmp/squash-root.img" ] && {
        file /tmp/squash-root.img | grep -q 'zstd compressed' && {
            Log "kdump.img compressed with zstd, when enable squash initrd option"
        }
    }
    popd

    # 2.w/o squash
    confile="${KDUMP_CONFIG}.nosquash"
    ConfigAny "dracut_args -o squash"
    file "${INITRD_KDUMP_IMG_PATH}" | grep "gzip compressed" && {
        Log "kdump.img compressed with gzip, when disable squash initrd option"
    }
    lsinitrd "${INITRD_KDUMP_IMG_PATH}" | grep -q "squash-root.img" && {
        Error "squash-root.img should not exist in kdump.img."
    }
    cp -f ${KDUMP_CONFIG} ${confile}
    RhtsSubmit "${confile}"

    # recover KDUMP_CONFIG
    Log "Recover the ${KDUMP_CONFIG}"
    cp -f ${confile} ${KDUMP_CONFIG}
    RestartKdump
}

MultihostStage "$(basename "${0%.*}")" CheckSquashRoot
