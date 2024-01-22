#!/bin/bash

function kvercmp()
{
    ver1=`echo $1 | sed 's/-/./'`
    ver2=`echo $2 | sed 's/-/./'`

    local ret=0
    i=1
    while [ 1 ]; do
        digit1=`echo $ver1 | cut -d . -f $i`
        digit2=`echo $ver2 | cut -d . -f $i`

        if ! [ "$digit1" -eq "$digit1" ] 2>/dev/null; then
            if ! [ "$digit2" -eq "$digit2" ] 2>/dev/null; then
                ret=0
                break
            else
                ret=-1
                break
            fi
        fi

        if ! [ "$digit2" -eq "$digit2" ] 2>/dev/null; then
            ret=1
            break
        fi

        if [ "$digit1" != "$digit2" ]; then
            if [ "$digit1" -lt "$digit2" ]; then
               ret=-1
               break
            fi
            ret=1
            break
        fi

        i=$((i+1))
    done

    echo "$ret"
}

function mytest()
{
    kvercmp '2.6.32-100.el6' '2.6.32-100.el6'
    kvercmp '2.6.32-100.el6' '2.6.32-101.el6'
    kvercmp '2.6.32-101.el6' '2.6.32-100.el6'
    kvercmp '2.6.32-101.el6' '3.1.4-0.2.el7.x86_64'
    kvercmp '3.1.4-0.2.el7.x86_64' `uname -r`
    kvercmp `uname -r` '3.1.4-0.1.el7.x86_64'
}
