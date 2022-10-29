#!/bin/bash
set -e

cd /sys/fs/cgroup/blkio
echo /bin/sleep > release_agent
echo 1 > notify_on_release

mkdir test
cd test
echo $$ > tasks
echo $$ > ../tasks
cd ..
rmdir test

