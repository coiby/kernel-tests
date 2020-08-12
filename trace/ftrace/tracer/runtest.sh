#!/bin/bash

FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)

rc=0
sh_files=""
sh_files+=" $CDIR/ftrace-tracer.sh"
for sh_file in $sh_files; do
    echo $sh_file
    bash $sh_file
    (( rc += $? ))
done

if [[ -f $(dirname $0)/../../include/testframeworks ]]; then
    source $(dirname $0)/../../include/testframeworks
    uploadlogs
fi

(( rc != 0 )) && exit 1 || exit 0
