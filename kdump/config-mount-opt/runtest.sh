#!/bin/sh

# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Source Kdump tests common functions.
. ../include/runtest.sh

MP=${MP:-/}
ACTION=${ACTION:-"add"}
VALUE1=${VALUE1:-""}
VALUE2=${VALUE2:-""}

ConfigMountOpts()
{
    if [ -z "$VALUE1" ]; then
        MajorError "Missing VALUE1."
    elif [ "$ACTION" = "replace" ] && [ -z "$VALUE2" ]; then
        MajorError "Missing VALUE12 for replacing."
    fi

    local ln_number=$(grep -n " $MP " "${FSTAB_FILE}" | cut -d: -f 1)
    [ -z "${ln_number}" ] && MajorError "No entry for mount point ${MP} in ${FSTAB_FILE}"

    # Note: ACITION add/remove/replace is manipulating
    # manipulating mount options for the entry with matching to the mount point

    local old_opts=$(grep  " $MP " "${FSTAB_FILE}" | awk '{print $4}')
    local new_opts=""

    case ${ACTION,,} in
        add)
            new_opts="${old_opts},${VALUE1}"
            ;;
        remove)
            new_opts="${old_opts//$VALUE1}"
            ;;
        replace)
            new_opts="${old_opts//$VALUE1/$VALUE2}"
            ;;
        override)
            new_opts="${VALUE1}"
            ;;
        *)
            FatalError "Invalid action '${ACTION}' for editing kdump sysconfig."
            ;;
    esac

    \cp "${FSTAB_FILE}" "${FSTAB_FILE}.tmp"

    sed -i "${ln_number}s/${old_opts//\//\\/}/${new_opts//\//\\/}/" "${FSTAB_FILE}.tmp"
    [ $? -ne 0 ] && MajorError "- Failed to update kdump ${FSTAB_FILE}."
    \mv "${FSTAB_FILE}.tmp" "${FSTAB_FILE}"
    cat "${FSTAB_FILE}"

    RhtsSubmit "${FSTAB_FILE}"
    sync;sync;sync

    # Restart kdump to make sure the mount options are processed in kdump initramfs.
    RestartKdump
}


# --- start ---
Multihost "ConfigMountOpts"

