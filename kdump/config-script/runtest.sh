#!/bin/sh

# Copyright (C) 2008 CAI Qian <caiqian@redhat.com>
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

TESTARGS=${TESTARGS:-""}
OUTPUT_TO_ROOT=${OUTPUT_TO_ROOT:-"true"}


# sys root will be always be mounted to /mnt/tmproot in kdump_{pre,post}.sh
ConfigScript()
{
    if [ -z "${OPTION}" ]; then
        MajorError "- No option is specified. Either kdump_pre or kdump_post."
    elif [ "${OPTION}" != "kdump_pre" ] && [ "${OPTION}" != "kdump_post" ]; then
        MajorError "- Invalid option: $OPTION. Only kdump_pre or kdump_post is allowed."
    fi

    CheckConfig
    cat <<EOF > "kdump_cmd.sh"
echo "--> Running cmds: $TESTARGS"
$TESTARGS
echo "--> Done running cmds"
EOF
    if [ "${OUTPUT_TO_ROOT,,}" = "true" ]; then
        cat /bin/kdump-1.sh kdump_cmd.sh /bin/kdump-2.sh > "/bin/${OPTION}.sh"
        sync
    else
        echo "echo '--> Start running kdump script'" > "/bin/${OPTION}.sh"
        cat kdump_cmd.sh >> "/bin/${OPTION}.sh"
    fi
    rm -f /bin/kdump-1.sh
    rm -f /bin/kdump-2.sh
    rm -f kdump_cmd.sh

    RhtsSubmit "/bin/${OPTION}.sh"
    chmod a+x "/bin/${OPTION}.sh"
    sync

    AppendConfig "${OPTION} /bin/${OPTION}.sh"
    RestartKdump
}


# ------ Start Here ------
Multihost "ConfigScript"
