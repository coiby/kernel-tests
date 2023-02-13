#!/bin/sh
chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_fio_12h_stress_bz1455553 "./main.sh"
