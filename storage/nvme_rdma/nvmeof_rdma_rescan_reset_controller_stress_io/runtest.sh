#!/bin/sh
chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_rescan_reset_controller_stress_io "./main.sh"
