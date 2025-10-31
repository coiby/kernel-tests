#!/bin/bash

# This test depends on an additional parition /luks or block device /dev/vdb
# which will be encrypted.
#
# If you use tmt to run the test, a test plan like follows will add an
# additional disk /dev/vdb with a size of 10GB
#
#   provision:
#      - name: client
#        how: virtual
#        hardware:
#           disk:
#             - size: = 40GB
#             - size: = 10GB
#
# If you use testing-farm, a test plan as follows will add an additional
# parition /luks,
#
#   provision:
#      - name: client
#        kickstart:
#          script: |
#              zerombr
#              clearpart --all
#              reqpart
#              part /boot --fstype=ext4 --size=2048
#              part / --fstype=xfs --size=4096 --grow
#              part /luks --fstype=xfs --size=10240
#          metadata: no_autopart
#
# Copyright (C) 2025 Coiby Xu <coxu@redhat.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Source Kdump tests common functions.
# shellcheck disable=SC1091
. ../include/runtest.sh

ConfigLUKS() {
	local tang_server

	[[ -z $1 ]] && FatalError "No tang server specified"

	if [ "$TMT_REBOOT_COUNT" == 0 ]; then
		if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
			# Abort entire recipeset if not reciving Done signal from server
			Log "[sync] Blocked till the server side is ready."
			rstrnt-sync-block -s "READY" "${SERVERS}" --timeout 3600 || FatalError "[sync] Not receiving READY signal from server"
		fi

		tang_server="http://$1"
		if ! curl -L "$tang_server"/adv &>/dev/null; then
			FatalError "Can't reach out to Tang server $tang_server"
		fi

		PASSWORD=kdump
		DEFAULT_LUKS_MP=/luks
		DEFAULT_LUKS_DEVICE=/dev/vdb
		if LUKS_DEVICE=$(findmnt -n -o SOURCE "$DEFAULT_LUKS_MP"); then
			LUKS_MP=$DEFAULT_LUKS_MP
			umount "$LUKS_MP"
			Log "Use $LUKS_DEVICE ($LUKS_MP) for LUKS volume"
		elif [[ -e $DEFAULT_LUKS_DEVICE ]]; then
			Log "Use $DEFAULT_LUKS_DEVICE for LUKS volume"
			LUKS_DEVICE=$DEFAULT_LUKS_DEVICE
			LUKS_MP=$DEFAULT_LUKS_MP
		else
MajorError "Neither is mount point $DEFAULT_LUKS_MP valid nor does device $DEFAULT_LUKS_DEVICE exist"
		fi

		VG_NAME=luks_vg
		LV_NAME=luks_lv
		echo $PASSWORD | cryptsetup luksFormat --force-password -q "$LUKS_DEVICE"
		uuid=$(blkid -s UUID -o value "$LUKS_DEVICE")
		CRYPTTAB_FILE=/etc/crypttab
		CRYPT_LINE="luks-$uuid UUID=$uuid"
		if [[ -e $CRYPTTAB_FILE ]] && ! grep -q "$CRYPT_LINE" "$CRYPTTAB_FILE"; then
			echo "$CRYPT_LINE" >>"$CRYPTTAB_FILE"
		elif [[ ! -e $CRYPTTAB_FILE ]]; then
			echo "$CRYPT_LINE" >"$CRYPTTAB_FILE"
			restorecon "$CRYPTTAB_FILE"
		fi
		echo $PASSWORD | cryptsetup luksOpen "$LUKS_DEVICE" "luks-$uuid"

		# Use clevis to unlock LUKS volume automatically
		# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/security_hardening/configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption_security-hardening#configuring-manual-enrollment-of-volumes-using-clevis_configuring-automated-unlocking-of-encrypted-volumes-using-policy-based-decryption
		echo $PASSWORD | clevis luks bind -y -d "$LUKS_DEVICE" tang '{"url":"'"${tang_server}"'"}'
		if ! clevis luks list -d "$LUKS_DEVICE" | grep -q "$tang_server"; then
			MajorError "Failed to bind LUKS device $LUKS_DEVICE"
		fi

		echo "hostonly_cmdline=yes" >/etc/dracut.conf.d/clevis.conf
		dracut -f --regenerate-all

		vgcreate "$VG_NAME" /dev/mapper/"luks-$uuid"
		lvcreate -n "$LV_NAME" -l 100%FREE "$VG_NAME"
		DUMP_DEVICE=/dev/"$VG_NAME"/"$LV_NAME"
		mkfs.xfs "$DUMP_DEVICE"
		dump_uuid=$(blkid -s UUID -o value "$DUMP_DEVICE")

		cp -f "${FSTAB_FILE}" fstab.old
		RhtsSubmit "${PWD}/fstab.old"
		sed -i "/ ${LUKS_MP//\//\\\/} /d" "${FSTAB_FILE}"

		# Mount the target to bypass https://issues.redhat.com/browse/RHEL-115835
		mkdir -p "$LUKS_MP"
		echo "UUID=$dump_uuid $LUKS_MP xfs" >>"$FSTAB_FILE"
		RhtsSubmit "${FSTAB_FILE}"

		# Configure Kdump target
		# ConfigFS requires LUKS_MP to be mounted
		mount "$DUMP_DEVICE" "$LUKS_MP"
		MP=${LUKS_MP} KPATH=/ RESTART_KDUMP=0 ConfigFS
		kdumpctl setup-crypttab
		sync
		RhtsReboot
	else
		kdumpctl restart
		Log "[sync] Client finished"
		if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
			rstrnt-sync-set -s "DONE"
		fi
	fi
}

if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
	Log "Run as client"
	TEST="${TEST}/client"
	ConfigLUKS "$SERVERS"
elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
	Log "Run as server"
	TEST="${TEST}/server"

	systemctl enable --now tangd.socket

	Log "[sync] Server is ready"
	rstrnt-sync-set -s "READY"

	# Abort only current task if not receving Done signal from client
	Log "[sync] Blocked till the client side is done."
	rstrnt-sync-block -s "DONE" "${CLIENTS}" --timeout 3600 || MajorError "[sync] Not receiving DONE signal from client"
else
	[[ -z $TANG_SERVER ]] && FatalError "Tang server not configured"
	# On Fedora rawhide, dracut-clevis has an issue that it can't resolve DNS when unlocking the
	# device so use IP instead.
	# https://github.com/latchset/clevis/issues/413
	tmp_ip_line=$(getent ahosts "$_TANG_SERVER" | grep -v : | head -n 1)
	if [[ -z $tmp_ip_line ]]; then
FatalError "Failed to get IP of Tang server $TANG_SERVER"
	fi
	if [[ -z $TANG_SERVER_PORT ]]; then
		tang_server_port=7500
	else
		tang_server_port=$TANG_SERVER_PORT
	fi
	tang_server_ip=$(echo "$tmp_ip_line" | awk '{print $1}')
	ConfigLUKS "${tang_server_ip}:${tang_server_port}"
fi

Report
