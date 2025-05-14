#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-2.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

kver_ret=0

# Usage:
#  kvercmp '2.6.32-100.el6' '2.6.32-100.el6'
#  kvercmp '2.6.32-100.el6' '2.6.32-101.el6'
#  kvercmp '2.6.32-101.el6' '3.1.4-0.2.el7.x86_64'
#  kvercmp '3.1.4-0.2.el7.x86_64' `uname -r`
#  kvercmp `uname -r` '3.1.4-0.1.el7.x86_64'
#
function kvercmp()
{
	ver1=$(echo $1 | sed 's/-/./')
	ver2=$(echo $2 | sed 's/-/./')

	ret=0
	i=1
	while [ 1 ]; do
		digit1=$(echo $ver1 | cut -d . -f $i)
		digit2=$(echo $ver2 | cut -d . -f $i)

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
	kver_ret=$ret

	echo "kvercmp($1,$2): $kver_ret"
}

# kernel_low <= $cver < kernel_high
function kernel_in_range()
{
	# shellcheck disable=SC2154
	kvercmp "$1" "$cver"
	if [ $kver_ret -le 0 ]; then
		kvercmp "$cver" "$2"
		if [ $kver_ret -lt 0 ]; then
			return 0
		fi
	fi
	return 1
}

# shellcheck disable=SC2062
function is_rhivos() { uname -r | grep -q el.*iv; }
function is_rhel() { grep -iq "red hat enterprise linux" /etc/system-release; }
function is_rhel9() { grep -q "release 9" /etc/redhat-release; }
function is_rhel10() { grep -q "release 10" /etc/redhat-release; }
