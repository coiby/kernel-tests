#!/bin/bash
#
# acpi-tables.sh: Collect ACPI tables from a system so they can be attached
#	to a BZ, plus a couple of other tidbits of info that may be of use.
#
# Copyright (c) 2018, Al Stone <ahs3@redhat.com>
# Copyright (c) 2019, Erico Nunes <ernunes@redhat.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

rlPhaseStartTest

TABLEDIR="/sys/firmware/acpi/tables"
WORKDIR="/tmp/acpi-table-$$"
TARBALL="/tmp/acpi-tables.tar.gz"

mkdir $WORKDIR
cd $WORKDIR

# copy in all the ACPI tables in binary form, and collect DMI info
rlRun "cp -r $TABLEDIR/* ."

# collect DMI info
set -o pipefail
rlRun "dmidecode | tee dmidecode.log"
set +o pipefail

# put it all in a tarball
chmod -R a+r *
rlRun "tar cvzf $TARBALL *"

# all done
echo "Tarball to attach is ready: $TARBALL"

rlFileSubmit $TARBALL
rm $TARBALL

rlPhaseEnd

rlJournalPrintText
rlJournalEnd
