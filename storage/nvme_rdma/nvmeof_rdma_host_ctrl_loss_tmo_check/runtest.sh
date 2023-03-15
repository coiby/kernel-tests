#!/bin/sh
chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_host_ctrl_loss_tmo_check "./main.sh"
