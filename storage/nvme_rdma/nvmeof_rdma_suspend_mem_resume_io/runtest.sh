#!/bin/sh

chmod +x main.sh
rhts-run-simple-test nvmeof_rdma_suspend_mem_resume_io "./main.sh"
