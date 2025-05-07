#!/bin/bash

sha256sum /sys/firmware/fdt | cut -d' ' -f1
