#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: This is a reproducer for bz1151823
#   Author: Li Wang <liwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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
        if uname -m | grep -v x86_64; then
            echo "Test skip from ${ARCH}"
            report_result Test_Skipped PASS 99
            exit 0
        fi
        cat << 'EOF' > cat32.c
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    FILE *file;
    int c;
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return EXIT_FAILURE;
    }
    file = fopen(argv[1], "r");
    if (file == NULL) {
        perror("Error opening file");
        return EXIT_FAILURE;
    }
    while ((c = fgetc(file)) != EOF) {
        putchar(c);
    }
    fclose(file);
    return EXIT_SUCCESS;
}
EOF
        rlRun "gcc -m32 cat32.c -o cat32"
    rlPhaseEnd

    rlPhaseStartTest
        # Run the test
        rlRun "for i in \$(seq 1 100); do ./cat32 /proc/self/maps | awk -F- '/libc\\.so/ {print \$1; exit;}'; done | awk '{mapping[\$1] += 1; if (mapping[\$1] >= 50) failed += 1;} END {if (failed == 0) print \"PASS\"; else print \"FAIL\";}'"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f cat32 cat32.c"
    rlPhaseEnd
rlJournalEnd
