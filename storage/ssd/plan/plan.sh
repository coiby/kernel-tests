#!/bin/bash
tmt run --environment "TEST_DEVS=nvme0n1 HOSTNAME=storageqe-62.rhts.eng.pek2.redhat.com" plan --name /storage/ssd/plan/ssd-remote -d -vvv
