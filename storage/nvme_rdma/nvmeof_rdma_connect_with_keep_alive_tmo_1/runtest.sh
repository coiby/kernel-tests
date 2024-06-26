#!/bin/sh
chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_connect_with_keep_alive_tmo_1 "./main.sh"
