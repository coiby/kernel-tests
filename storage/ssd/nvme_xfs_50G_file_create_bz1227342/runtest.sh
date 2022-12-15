#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvme_xfs_50G_file_create_bz1227342 "./main.sh"
