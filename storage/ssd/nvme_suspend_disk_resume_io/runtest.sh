#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvme_suspend_disk_resume_io "./main.sh"
