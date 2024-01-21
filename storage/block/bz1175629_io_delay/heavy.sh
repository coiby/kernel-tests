#!/bin/bash
echo "#########"
# shellcheck disable=SC2154
echo "Now, we are starting heavy async writes to $MNT/data on $target."

# shellcheck disable=SC2034
for i in `seq 5`; do
    dd if=/dev/zero of=/tmp/mnt/data bs=1G count=50 &> /dev/null
done

exit 0
