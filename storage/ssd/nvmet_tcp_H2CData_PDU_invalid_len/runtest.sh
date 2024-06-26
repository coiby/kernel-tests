#!/bin/bash

chmod +x main.sh
rhts-run-simple-test nvmet_tcp_H2CData_PDU_invalid_len "./main.sh"
