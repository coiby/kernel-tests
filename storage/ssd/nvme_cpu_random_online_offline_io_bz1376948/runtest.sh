#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvme_cpu_random_online_offline_io_bz1376948 "./main.sh"
