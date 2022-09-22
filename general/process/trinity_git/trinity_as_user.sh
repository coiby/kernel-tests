#!/bin/sh
echo "Checking if user dummy exists"
id dummy
if [ $? -ne 0 ]; then
    echo "Creating user dummy"
    adduser dummy
fi
echo "Running trinity_test.sh"
su dummy ./trinity_test.sh

