#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvme_driver_null_pointer_with_reboot_bz1422521 "./main.sh"
