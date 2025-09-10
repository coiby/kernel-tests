#!/bin/bash

set -e

gcc syscalls_list.c -o syscalls_list

./syscalls_list
