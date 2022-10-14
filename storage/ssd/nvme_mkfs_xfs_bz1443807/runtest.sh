#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvme_mkfs_xfs_bz1443807 "./main.sh"
