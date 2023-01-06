#!/bin/sh
chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_reset_controller_stress "./main.sh"
