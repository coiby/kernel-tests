#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Wang Shu <shuwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1


rlJournalStart
    rlPhaseStartSetup
        useradd test
    rlPhaseEnd

    rlPhaseStartTest Test
        rlRun "bash -c 'ulimit -s 1024; /bin/true'"
        rlRun "su test -c 'ulimit -s 1024; /bin/true'"

        rlRun "gcc map_growsdown.c -o map_growsdown"
        rlRun "./map_growsdown"

        java_version="1.7.0"

        if rlIsRHEL "9" || rlIsCentOS "9"; then
            java_version="1.8.0"
        fi

        if stat /run/ostree-booted > /dev/null 2>&1; then
            rpm-ostree install -A --idempotent --allow-inactive java-${java_version}-openjdk java-${java_version}-openjdk-devel
        else
            yum install -y java-${java_version}-openjdk java-${java_version}-openjdk-devel
        fi

        if [ $? != "0" ]; then
            rstrnt-report-result JVM_Test_Skipped PASS 99

            rlPhaseEnd
            rlJournalEnd
            rlJournalPrintText
            exit 0;
        fi

        LIBPATH=$(find /usr/lib/jvm/java-${java_version}/jre/lib -name libjvm.so | grep server)
        LIBPATH=$(dirname $LIBPATH)
        LIBFFIPATH=$(find /usr/lib/jvm/java-${java_version}/jre/lib -name libffi.so.6 | head -1)
        LIBFFIPATH=$(dirname $LIBFFIPATH)
        if [ -n "${LIBFFIPATH}" ]; then
            rlRun "gcc -fPIC -I/usr/lib/jvm/java-${java_version}/include/ -I/usr/lib/jvm/java-${java_version}/include/linux/  -L $LIBPATH -Wl,-rpath=${LIBFFIPATH} -ljvm jni-sanity.c -o jni-sanity"
            rlRun "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${LIBPATH}:${LIBFFIPATH} ./jni-sanity"
        else
            rlRun "gcc -fPIC -I/usr/lib/jvm/java-${java_version}/include/ -I/usr/lib/jvm/java-${java_version}/include/linux/  -L $LIBPATH -ljvm jni-sanity.c -o jni-sanity"
            rlRun "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${LIBPATH} ./jni-sanity"
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText

