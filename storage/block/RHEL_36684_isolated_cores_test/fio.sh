#!/bin/bash

    TEST_DIR=/home/fiotest
    mkdir -p ${TEST_DIR}

    fio --name=write_throughput --directory=${TEST_DIR} --numjobs=8 \
        --size=10G --time_based --runtime=60s --ramp_time=2s --ioengine=libaio \
        --direct=1 --verify=0 --bs=1M --iodepth=64 --rw=write \
        --group_reporting=1
    rm -rf ${TEST_DIR:?}/*

    fio --name=write_iops --directory=${TEST_DIR} --size=10G \
        --time_based --runtime=60s --ramp_time=2s --ioengine=libaio --direct=1 \
        --verify=0 --bs=4K --iodepth=64 --rw=randwrite --group_reporting=1
    rm -rf ${TEST_DIR:?}/*

    fio --name=read_throughput --directory=${TEST_DIR} --numjobs=8 \
        --size=10G --time_based --runtime=60s --ramp_time=2s --ioengine=libaio \
        --direct=1 --verify=0 --bs=1M --iodepth=64 --rw=read \
        --group_reporting=1
    rm -rf ${TEST_DIR:?}/*

    fio --name=read_iops --directory=${TEST_DIR} --size=10G \
        --time_based --runtime=60s --ramp_time=2s --ioengine=libaio --direct=1 \
        --verify=0 --bs=4K --iodepth=64 --rw=randread --group_reporting=1
    rm -rf ${TEST_DIR:?}/*
