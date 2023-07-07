#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/firmware/linux-firmware/sanity
#   Description: Sanity check for linux-firmware files
#   Author: Erico Nunes <ernunes@redhat.com>
#   Update: Laura Trivelloni <ltrivell@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

HASHES_FILE=/tmp/hashes
FILETYPES_FILE=/tmp/filetypes

rm -f "$HASHES_FILE"
rm -f "$FILETYPES_FILE"

pushd /usr/lib/firmware

# Check for broken links
broken=$(find -L . -type l)
if [[ $(find -L . -type l) == '' ]]
then
	echo "No broken links found."
else
	echo "Broken links: $broken"
fi


# We strip the absolute path prefix, so that it is easier to compare later with
# relative paths
for f in $( rpm -ql linux-firmware | grep /usr/lib/firmware/ | sed 's@/usr/lib/firmware/@@' )
do
    # skip directories
    [ -f "$f" ] || continue

    # check if symbolic link
    if [[ -L "$f" ]]
    then
	slink="$f"
        f=$(readlink -f "$f")
	# remove /usr/lib/firmware/ from the absolute path
	f=${f##*firmware/}
	if [ ! -f "$f" ]
	then
		echo "$slink -> $f doesn't exists"
	fi
    fi

    if [[ "$f" == *.xz ]]
    then
	# decompress to have same filetype found in linux-firmware repository
	# -k option to keep the original *.xz file
        xz -d -k $f
	# remove .xz extension from current filename
        f="${f%.*}"
    fi

    sha256sum "$f" >> "$HASHES_FILE"
    file -r -F '' "$f" >> "$FILETYPES_FILE"

    # remove extracted file from /usr/lib/firmware
    rm -f "$f"
done
popd

LINUX_FIRMWARE_RELEASE="$(rpm -q --queryformat '%{release}\n' linux-firmware)"
# This expression strips just the sha1 part between "git" and ".el7".
UPSTREAM_SHA1="$(sed -e 's/[0-9]\+\.git\([0-9a-z]\+\)\..*/\1/g' - <<< "$LINUX_FIRMWARE_RELEASE")"

cd /tmp
git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
cd linux-firmware
git checkout "$UPSTREAM_SHA1"

# Check sha256sum of files. This will check all files.
if ! sha256sum --quiet -c "$HASHES_FILE"
then
    sha256sumresult=FAIL
else
    sha256sumresult=PASS
fi
report_result "sha256sum" "$sha256sumresult"

# Compare file type for all files.
# Might be useful information in case we got a mismatch
fileresult=PASS
while read -r filetype_line
do
    filename="$(cut -d ' ' -f 1  - <<< "$filetype_line")"
    filetype="$(cut -d ' ' -f 2- - <<< "$filetype_line")"
    thisfiletype="$(file -r -b "$filename")"
    if [ "$thisfiletype" != "$filetype" ]
    then
        fileresult=FAIL
        echo "  mismatch on file $filename"
        echo "  found:    $filetype"
        echo "  expected: $thisfiletype"
    fi
done < "$FILETYPES_FILE"
report_result "file" "$fileresult"

