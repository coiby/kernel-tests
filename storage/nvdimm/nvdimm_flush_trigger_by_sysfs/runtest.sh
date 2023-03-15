#!/bin/bash
chmod +x main.sh
rhts-run-simple-test nvdimm_flush_trigger_by_sysfs "./main.sh"
