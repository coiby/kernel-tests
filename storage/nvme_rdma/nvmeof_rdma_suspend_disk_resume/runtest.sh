#!/bin/sh

chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_suspend_disk_resume "./main.sh"
