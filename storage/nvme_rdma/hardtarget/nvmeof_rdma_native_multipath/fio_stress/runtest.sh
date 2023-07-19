#!/bin/sh

chmod +x main.sh
rhts-run-simple-test fio_stress "./main.sh"
