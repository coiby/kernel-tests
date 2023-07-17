#!/bin/bash

chmod +x main.sh
rhts-run-simple-test nvme_format_command_test_bz1449838 "./main.sh"
