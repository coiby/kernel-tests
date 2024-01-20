#!/bin/bash
. ../include/runtest.sh || . /mnt/tests/kernel/vm/sysctl/include/runtest.sh || exit 1

TARGET_FILE="/proc/sys/vm/min_free_kbytes"
TMP_FILE=`mktemp /tmp/min_free_kbytes.XXXXXX`
OLD_TUNE=

function get_min_free_kbytes()
{
    min_free_kbytes=`cat ${TARGET_FILE}`
    echo ${min_free_kbytes}
}

function get_mem_total()
{
    mem_total=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
    echo ${mem_total}
}

function get_mem_free()
{
    mem_free=`cat /proc/meminfo | grep MemFree | awk '{print $2}'`
    echo ${mem_free}
}

function test_run()
{
    for X in `seq 2 5`; do
        mem_free=`get_mem_free`
        echo "before testing, mem_free: ${mem_free}"

        N=$((10 - $X))
        min_free_kbytes=`expr ${mem_free} / ${N}`

        echo ${min_free_kbytes} > ${TARGET_FILE}
        verify_tune_value ${TARGET_FILE} ${min_free_kbytes}

        dd_size=$((${mem_free}+1024*${X}))
        root_size=`df -k / |grep -v "^Filesystem" |awk '{print $4}'`
        if [ $dd_size -lt $root_size ]; then
            dd_size=$((${dd_size}/100))
        else
            dd_size=$((${root_size}*2/300))
        fi
        dd if=/dev/zero of=${TMP_FILE}${X} bs=${dd_size}k count=100

        sleep 2
        mem_free=`get_mem_free`
        echo "after testing, mem_free is ${mem_free}"
        echo "min_free_kbytes is ${min_free_kbytes}"

        if [ ${min_free_kbytes} -gt ${mem_free} ]; then
            echo "TestError: min_free_kbytes Failed"
            echo ${OLD_TUNE} > ${TARGET_FILE}
            exit 1
        fi
    done
    rm -rf ${TMP_FILE}*
}

function main()
{
    check_file_exist ${TARGET_FILE}
    OLD_TUNE=`get_min_free_kbytes`

    test_run
    echo ${OLD_TUNE} > ${TARGET_FILE}
    echo "PASS: min_free_kbytes PASS"
}

main
