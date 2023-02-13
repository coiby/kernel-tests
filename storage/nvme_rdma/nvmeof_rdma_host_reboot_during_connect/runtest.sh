#!/bin/sh
chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_host_reboot_during_connect "./main.sh"
