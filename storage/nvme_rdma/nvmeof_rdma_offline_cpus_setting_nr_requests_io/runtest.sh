#!/bin/sh
chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_offline_cpus_setting_nr_requests_io "./main.sh"
