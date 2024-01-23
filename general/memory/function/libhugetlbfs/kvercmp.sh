#!/bin/bash

kver_ret=0
function kvercmp()
{
	local ver1=`echo $1 | sed 's/-/./'`
	local ver2=`echo $2 | sed 's/-/./'`

	local ret=0
	local i=1
	while [ 1 ]; do
		local digit1=`echo $ver1 | cut -d . -f $i`
		local digit2=`echo $ver2 | cut -d . -f $i`

		if [ -z "$digit1" ]; then
			if [ -z "$digit2" ]; then
				ret=0
				break
			else
				ret=-1
				break
			fi
		fi

		if [ -z "$digit2" ]; then
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
	# it's used by the caller.
	# shellcheck disable=SC2034
	kver_ret=$ret
	echo "kvercmp($1,$2): $ret"
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
