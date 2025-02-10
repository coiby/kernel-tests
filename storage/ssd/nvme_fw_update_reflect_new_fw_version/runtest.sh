#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

function runtest() {

	SSD_RM_Unused_VG

	SSD_RM_Unused_Partitions

	get_nvme_disk

	if rlIsRHEL "9" || rlIsRHEL "8"; then
		tlog "Tesing NVMe FW update on RHEL8 and RHEL9"
	else
		tlog "Skip test because NVMe FW update only support on RHEL8 and RHEL9"
		rstrnt-report-result "$TNAME" SKIP
		exit 0
	fi

	FW_2_3_0="Express-Flash-PCIe-SSD_Firmware_637P6_LN64_2.3.0_A04_01.BIN"
	FW_2_5_0="Express-Flash-PCIe-SSD_Firmware_5V3P7_LN64_2.5.0_A05_01.BIN"
	FW_2_3_0_URL="https://s3.amazonaws.com/arr-cki-prod-lookaside/lookaside/static/${FW_2_3_0}"
	FW_2_5_0_URL="https://s3.amazonaws.com/arr-cki-prod-lookaside/lookaside/static/${FW_2_5_0}"
	nvme_model="Dell Ent NVMe v2 AGN RI U.2 1.92TB"
	if [ ! -f "$FW_2_3_0" ]; then
		tok "wget ${FW_2_3_0_URL}"
	fi
	if [ ! -f "$FW_2_5_0" ]; then
		tok "wget ${FW_2_5_0_URL}"
	fi
	tok chmod +x "$FW_2_3_0" "$FW_2_5_0"

for DISK in $DISKS; do
	MODEL=$(cat /sys/block/"$DISK"/device/model)
	if [[ $MODEL =~ ${nvme_model} ]]; then
		tlog "Start to update nvme disk:$MODEL with FW_2_3_0:$FW_2_3_0"
		tok "nvme list"
		tok "./$FW_2_3_0 -q -f"
		tok "nvme list"
		up_ver=$(nvme list | grep "$nvme_model" | awk '{print $NF}')
		if [ "$up_ver" = "2.3.0" ]; then
			tlog "Update nvme:$MODEL to FW:2.3.0 pass"
		else
			tnot "echo Update nvme:$MODEL to FW:2.3.0 failed"
		fi

		tlog "Start to update nvme disk:$MODEL with FW_2_5_0:$FW_2_5_0"
		tok "nvme list"
		tok "./$FW_2_5_0 -q -f"
		tok "nvme list"
		up_ver=$(nvme list | grep "$nvme_model" | awk '{print $NF}')
		if [ "$up_ver" = "2.5.0" ]; then
			tlog "Update nvme:$MODEL to FW:2.5.0 pass"
		else
			tnot "echo Update nvme:$MODEL to FW:2.5.0 failed"
		fi
	else
		continue
	fi
done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
