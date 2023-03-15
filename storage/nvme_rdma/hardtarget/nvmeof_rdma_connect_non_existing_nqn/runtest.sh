#!/bin/bash

chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_connect_non_existing_nqn "./main.sh"
