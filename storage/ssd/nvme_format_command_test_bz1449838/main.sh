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

for DISK in $DISKS; do
	MODEL=$(cat /sys/block/"$DISK"/device/model)
	tlog "The testing disk $DISK model is $MODEL"
	if rlIsRHEL ">7" || rlIsFedora; then
		for lbaf in 0 1; do
			if [[ $lbaf == 1 ]]; then
				if [[ $MODEL =~ "INTEL SSDPEDMD016T4" ]]; then
					continue
				fi
			fi
			for ses in 0 1 2; do
				for pi in 0 1 2 3; do
					if [[ $lbaf == 0 && $pi != 0 ]]; then
						if [[ $MODEL =~ "Dell Express Flash PM1725a"|"Dell Express Flash NVMe PM1725 "|"Samsung SSD 983 DCT"|"Micron_9300_MTFDHAL3T8TDP"|"Dell Ent NVMe v2 AGN RI U.2"|"INTEL SSDPEDMD016T4"|"Dell Express Flash NVMe P4600"|"SAMSUNG MZQL2960HCJR-00A07"|"Dell Ent NVMe CM6 RI"|"Dell Ent NVMe P5500 RI U.2"|"SAMSUNG MZWLL1T6HAJQ-00005"|"SAMSUNG MZPLJ1T6HBJR-00007" ]]; then
							continue
						fi
					elif [[ $lbaf == 1 && $pi != 0 ]]; then
						if [[ $MODEL =~ "Micron_9300_MTFDHAL3T8TDP"|"Samsung SSD 983 DCT"|"SAMSUNG MZQL2960HCJR-00A07"|"Dell Express Flash NVMe P4600"|"Dell Ent NVMe P5500 RI U.2" ]]; then
							continue
						fi
					fi
					for pil in 0 1; do
						if [[ $lbaf == 0 && $pi == 0 && $pil == 1 ]]; then
							if [[ $MODEL =~ "Dell Ent NVMe CM6 RI" ]]; then
								continue
							fi
						fi
						for ms in 0 1; do
							if [[ $lbaf == 1 && $pi != 0 && $ms == 1 ]]; then
								if [[ $MODEL =~ "Dell Express Flash PM1725a"|"SAMSUNG MZWLL1T6HAJQ-00005" ]]; then
									tlog "$DISK: --lbaf=$lbaf --ses=$ses --pi=$pi --pil=$pil --ms=$ms, dd read I/O error, BZ2081716, skipping"
									continue
								fi
							elif [[ $lbaf == 1 && $pi == 0 && $ms == 1 ]]; then
								if [[ $MODEL =~ "Dell Express Flash PM1725a"|"Dell Express Flash NVMe PM1725 "|"Dell Ent NVMe v2 AGN RI U.2"|"Dell Ent NVMe CM6 RI"|"Dell Ent NVMe P5500 RI U.2"|"SAMSUNG MZWLL1T6HAJQ-00005"|"SAMSUNG MZPLJ1T6HBJR-00007" ]]; then
									tlog "$DISK: --lbaf=$lbaf --ses=$ses --pi=$pi --pil=$pil --ms=$ms, /dev/$DISK node disappeared, BZ2081713, skipping"
									continue
								fi
							fi
							dmesg -c >/dev/null
							tok "nvme format /dev/$DISK --lbaf=$lbaf --ses=$ses --pi=$pi --pil=$pil --ms=$ms -r -f"
							# shellcheck disable=SC2181
							if [ $? -ne 0 ]; then
								tlog "$DISK: --lbaf=$lbaf --ses=$ses --pi=$pi --pil=$pil --ms=$ms not support" | tee -a format_fail
								continue
							fi
							sleep 1
							if [[ $lbaf == 0 && $ses == 0 && $pi == 0 && $pil == 0 && $ms == 0 ]]; then
								if [[ $MODEL =~ "Micron_9300_MTFDHAL3T8TDP" ]]; then
									trun "dd if=/dev/$DISK of=/dev/null bs=4096 count=100000"
								else
									tok "dd if=/dev/$DISK of=/dev/null bs=4096 count=100000"
								fi

							fi
							# shellcheck disable=SC2181
							if [ $? -ne 0 ]; then
								tlog "$DISK: --lbaf=$lbaf --ses=$ses --pi=$pi --pil=$pil --ms=$ms with dd operation failed" | tee -a dd_fail
							fi
							tok "fdisk -l /dev/$DISK"
							# shellcheck disable=SC2181
							if [ $? -ne 0 ]; then
								tlog "$DISK: --lbaf=$lbaf --ses=$ses --pi=$pi --pil=$pil --ms=$ms with fdisk -l operation failed" | tee -a fdisk_fail
							fi
							dmesg | grep "blk_update_request: operation not supported error" && tlog "$DISK: --lbaf=$lbaf --ses=$ses --pi=$pi --pil=$pil --ms=$ms: dmesg check failed" | tee -a dmesg_check_fail
							tok "nvme format /dev/$DISK --lbaf=0 -f"
							tok "dd if=/dev/$DISK of=/dev/null bs=4096 count=100000"
						done
					done
				done
			done
		done
	fi
done
}

tlog "running $0"
trun "uname -a"
runtest
tend
