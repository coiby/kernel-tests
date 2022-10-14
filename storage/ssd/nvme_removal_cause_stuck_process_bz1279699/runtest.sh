#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvme_removal_cause_stuck_process_bz1279699 "./main.sh"
