#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvme_pci_adapter_rescan_reset_remove_bz1370507 "./main.sh"
