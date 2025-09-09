#!/bin/bash
#
# Copyright (c) 2023 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

WORKING_DIR=/tmp/erofs

git clone https://github.com/erofs/erofs-utils.git "${WORKING_DIR}"
cd $WORKING_DIR || exit
git checkout experimental-tests
autoupdate
./autogen.sh
./configure --disable-lz4
export srcdir="$WORKING_DIR"/tests/erofs

make check

# process results
file_list=("$WORKING_DIR/tests/results/erofs"/*)
SKIP_LIST="$TEST_PARAM_SKIP_LIST"
files_to_chk_status=()
for file in "${file_list[@]}"; do
    filename="$(basename "$file")"
    chk_status=true
    for skip_entry in $SKIP_LIST; do
        if [[ "$filename" == "$skip_entry"* ]]; then
            rstrnt-report-result -o "$WORKING_DIR/tests/results/erofs/$filename" SKIP_LIST_erofs/"$filename" SKIP
            chk_status=false
            break
        fi
    done
    if [ "$chk_status" = true ]; then
        files_to_chk_status+=("$file")
    fi
done

for file in "${files_to_chk_status[@]}"; do
    if [ -f "$file" ]; then
        filename="$(basename "$file")"
        extension="${filename##*.}"
        case "$extension" in
            bad)
                rstrnt-report-result -o "$WORKING_DIR/tests/results/erofs/$filename" erofs/"$filename" FAIL
                ;;
            notrun)
                rstrnt-report-result -o "$WORKING_DIR/tests/results/erofs/$filename" erofs/"$filename" SKIP
                ;;
            full)
                rstrnt-report-result -o "$WORKING_DIR/tests/results/erofs/$filename" erofs/"$filename" PASS
                ;;
            *)
                rstrnt-report-result -o "$WORKING_DIR/tests/results/erofs/$filename" erofs/"$filename" WARN
                echo "Unknown file extension: $extension for $filename"
                ;;
        esac
    fi
done
