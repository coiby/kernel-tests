#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvme_controller_reset_goes_offline_bz1334462 "./main.sh"
