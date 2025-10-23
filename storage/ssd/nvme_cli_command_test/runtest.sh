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

	tok "nvme list"

	# RHEL-121216
	tok "nvme list --output-format=json | jq -r '.Devices[]|.DevicePath' | grep nvme[0-9]n[0-9]"

for DISK in $DISKS; do

	NVME_CHAR=/dev/${DISK:0:5}
	NVME_DISK=/dev/${DISK}
	MODEL=$(cat /sys/block/"$DISK"/device/model)
	tlog "The testing disk $DISK model is $MODEL"
	tok "nvme list"
	tok "nvme list-subsys -o json"
	tok "nvme id-ctrl ${NVME_DISK}"
	tok "nvme id-ns ${NVME_DISK}"

	if [[ $MODEL =~ "INTEL SSDPEDMX400G4"|"INTEL SSDPEDMD016T4"|"Dell Express Flash NVMe P4800X" ]]; then
		tnot "nvme list-ns ${NVME_DISK}"
	else
		tok "nvme list-ns ${NVME_DISK}"
	fi

	if [[ $MODEL =~ "Dell Express Flash PM1725a"|"Dell Express Flash NVMe PM1725 "|"Micron_9300_MTFDHAL3T8TDP"|"Samsung SSD 983 DCT"|"Dell Express Flash NVMe P4600"|"SAMSUNG MZWLL1T6HAJQ-00005"|"Dell Express Flash PM1725b"|"Dell Express Flash NVMe P4800X"|"Dell Express Flash NVMe P4500" ]]; then
		tnot "nvme ns-descs ${NVME_DISK} -n 1"
	else
		tok "nvme ns-descs ${NVME_DISK} -n 1"
	fi

	if [[ $MODEL =~ "Dell Ent NVMe CM6 RI"|"KIOXIA KCMYDRUG1T92" ]]; then
		tok "nvme id-nvmset ${NVME_DISK}"
	else
		tnot "nvme id-nvmset ${NVME_DISK}"
	fi

	if [[ $MODEL =~ "Dell Express Flash PM1725a"|"Dell Express Flash NVMe PM1725 "|"Dell Express Flash NVMe P4600"|"Dell Express Flash PM1725b"|"Dell Express Flash NVMe P4800X"|"Dell Express Flash NVMe P4500" ]]; then
		tnot "nvme list-ctrl ${NVME_DISK}"
	else
		tok "nvme list-ctrl ${NVME_DISK}"
	fi

	tok "nvme get-ns-id ${NVME_DISK}"
	tok "nvme get-log --log-id=2 --log-len=512 ${NVME_DISK}"

	trun "nvme telemetry-log ${NVME_CHAR} --output-file=telemetry_log.bin"

	tok "nvme fw-log ${NVME_DISK}"

	if [[ $MODEL =~ "SAMSUNG MZ1L21T9HCLS-00A07"|"SAMSUNG MZQL21T9HCJR-00A07"|"Micron_9300_MTFDHAL3T8TDP"|"SAMSUNG MZQL2960HCJR-00A07"|"Dell Ent NVMe v2 AGN RI U.2"|"Dell Ent NVMe CM6 RI"|"SAMSUNG MZWLL1T6HAJQ-00005"|"SAMSUNG MZPLJ1T6HBJR-00007"|"Dell Ent NVMe v2 AGN FIPS MU"|"SAMSUNG MZWLO1T9HCJR-00A07"|"KIOXIA KCMYDRUG1T92"|"SAMSUNG MZWL6960HFJA-00AW7" ]]; then
		tok "nvme changed-ns-list-log ${NVME_CHAR}"
	else
		tnot "nvme changed-ns-list-log ${NVME_CHAR}"
	fi

	tok "nvme smart-log ${NVME_DISK}"
	tok "nvme error-log ${NVME_DISK}"

	if [[ $MODEL =~ "Dell Express Flash NVMe PM1725" ]]; then
		tnot "nvme effects-log ${NVME_CHAR}"
	else
		trun "nvme effects-log ${NVME_CHAR}"
	fi

	tnot "nvme endurance-log ${NVME_CHAR} --output=binary"
	tok "nvme get-feature ${NVME_DISK} -f 1"
	tok "nvme get-feature ${NVME_DISK} -f 2"

	if [[ $MODEL =~ "INTEL SSDPEDMX400G4"|"Micron_9300_MTFDHAL3T8TDP"|"INTEL SSDPEDMD016T4"|"Dell Express Flash NVMe P4600"|"Dell Ent NVMe P5500 RI U.2"|"Dell Express Flash NVMe P4800X"|"Dell Express Flash NVMe P4500" ]]; then
		tnot "nvme get-feature ${NVME_DISK} -f 3"
	else
		tok "nvme get-feature ${NVME_DISK} -f 3"
	fi

	tok "nvme get-feature ${NVME_DISK} -f 4"
	tok "nvme get-feature ${NVME_DISK} -f 5"

	if [[ $MODEL =~ "SAMSUNG MZ1L21T9HCLS-00A07"|"SAMSUNG MZQL21T9HCJR-00A07"|"SAMSUNG MZQL2960HCJR-00A07"|"Dell Ent NVMe v2 AGN RI U.2"|"Dell Ent NVMe CM6 RI"|"Dell Ent NVMe P5500 RI U.2"|"SAMSUNG MZPLJ1T6HBJR-00007"|"Dell Express Flash PM1725b"|"Dell Ent NVMe v2 AGN FIPS MU"|"SAMSUNG MZWLO1T9HCJR-00A07"|"KIOXIA KCMYDRUG1T92"|"SAMSUNG MZWL6960HFJA-00AW7" ]]; then
		tok "nvme device-self-test ${NVME_DISK} -s 1"
	else
		tnot "nvme device-self-test ${NVME_DISK} -s 1"
	fi

	if [[ $MODEL =~ "Dell Express Flash NVMe P4600"|"Dell Express Flash NVMe P4500" ]]; then
		tnot "nvme set-feature ${NVME_CHAR} -f 2 -v 0x0"
	else
		tok "nvme set-feature ${NVME_CHAR} -f 2 -v 0x0"
	fi

	if [[ $MODEL =~ "Dell Express Flash NVMe P4800X" ]]; then
		tlog "RHEL-26196: skip nvme format for $MODEL"
	else
		tok "nvme format ${NVME_DISK} --lbaf=0 -f"
	fi
	tok "nvme admin-passthru ${NVME_CHAR} --opcode=06 --data-len=4096 --cdw10=1 -r"

	if [[ $MODEL =~ "Dell Express Flash NVMe P4800X" ]]; then
		trun "nvme io-passthru ${NVME_DISK} --opcode=2 --namespace-id=1 --data-len=4096 --read --cdw10=0 --cdw11=0 --cdw12=0x70000 --raw-binary"
	else
		tok "nvme io-passthru ${NVME_DISK} --opcode=2 --namespace-id=1 --data-len=4096 --read --cdw10=0 --cdw11=0 --cdw12=0x70000 --raw-binary"
	fi

	tlog "TODO: nvme  security-send"
	tlog "TODO: nvme security-recv"
	tlog "TODO: nvme resv-acquire"
	tlog "TODO: nvme resv-register"
	tlog "TODO: nvme resv-report"
	tok "nvme dsm ${NVME_DISK} -n 1 -d -s \"100,200,300,400,500,600,700,800,900,1000\" -b \"10,10,10,10,10,10,10,10,10,10\""
	tok "nvme flush ${NVME_DISK}"
	tlog "TODO: nvme compare"
	tlog "TODO: nvme read"
	tlog "TODO: nvme write"
	tlog "TODO: nvme write-zeroes"

	# Need format again if NVME Write Uncorrectable Succes
	if [[ $MODEL =~ "Micron_9300_MTFDHAL3T8TDP"|"Dell Express Flash NVMe PM1725 " ]]; then
		tnot "nvme write-uncor -s 0 -c 512 ${NVME_DISK}"
	else
		tok "nvme write-uncor -s 0 -c 512 ${NVME_DISK}"
	fi

	if [[ $MODEL =~ "Dell Express Flash NVMe P4800X" ]]; then
		tlog "RHEL-26196: skip nvme format for $MODEL"
	else
		tok "nvme format ${NVME_DISK} --lbaf=0 -f"
	fi

	if [[ $MODEL =~ "SAMSUNG MZ1L21T9HCLS-00A07"|"SAMSUNG MZQL21T9HCJR-00A07"|"SAMSUNG MZQL2960HCJR-00A07"|"Dell Ent NVMe v2 AGN RI U.2"|"Dell Ent NVMe CM6 RI"|"Dell Ent NVMe P5500 RI U.2"|"SAMSUNG MZPLJ1T6HBJR-00007"|"Dell Ent NVMe v2 AGN FIPS MU"|"SAMSUNG MZWLO1T9HCJR-00A07"|"KIOXIA KCMYDRUG1T92"|"SAMSUNG MZWL6960HFJA-00AW7" ]]; then
		tok "nvme sanitize ${NVME_DISK} -a 0x02"
	else
		tnot "nvme sanitize ${NVME_DISK} -a 0x02"
	fi

	if [[ $MODEL =~ "SAMSUNG MZ1L21T9HCLS-00A07"|"SAMSUNG MZQL21T9HCJR-00A07"|"Dell Ent NVMe v2 AGN RI U.2"|"Dell Ent NVMe CM6 RI"|"Dell Ent NVMe P5500 RI U.2"|"SAMSUNG MZQL2960HCJR-00A07"|"SAMSUNG MZPLJ1T6HBJR-00007"|"Dell Ent NVMe v2 AGN FIPS MU"|"SAMSUNG MZWLO1T9HCJR-00A07"|"KIOXIA KCMYDRUG1T92"|"SAMSUNG MZWL6960HFJA-00AW7" ]]; then
		tok "nvme sanitize-log ${NVME_DISK}"
	else
		tnot "nvme sanitize-log ${NVME_DISK}"
	fi

	tok "nvme reset ${NVME_CHAR}"

	if [[ $MODEL =~ "Dell Express Flash PM1725a"|"SAMSUNG MZPLJ1T6HBJR-00007"|"Dell Express Flash PM1725b" ]]; then
		tlog "Skip nvme subsystem-reset on $MODEL, Bug 1699599"
	elif [[ $MODEL =~ "INTEL SSDPEDMD016T4"|"Dell Express Flash NVMe P4600"|"Micron_9300_MTFDHAL3T8TDP"|"Dell Ent NVMe P5500 RI U.2"|"Dell Express Flash NVMe PM1725 "|"Dell Express Flash NVMe P4800X"|"Dell Express Flash NVMe P4500" ]]; then
		tnot "nvme subsystem-reset ${NVME_CHAR}"
		tlog "nvme subsystem-reset not support on $DISK, MODEL:\"$MODEL\""
	elif [[ $MODEL =~ "SAMSUNG MZ1L21T9HCLS-00A07"|"SAMSUNG MZQL21T9HCJR-00A07"|"Samsung SSD 983 DCT"|"Dell Ent NVMe v2 AGN RI U.2"|"SAMSUNG MZQL2960HCJR-00A07"|"Dell Ent NVMe CM6 RI" ]]; then
		tlog "nvme subsystem-reset on $DISK lead disk disappeared, BZ2093136"
	elif [[ $MODEL =~ "Dell Ent NVMe v2 AGN FIPS MU"|"SAMSUNG MZWLO1T9HCJR-00A07" ]]; then
		tlog "Skip nvme subsystem-reset on $MODEL, lead Link Down"
	else
		tok "nvme subsystem-reset ${NVME_CHAR}"
	fi

	trun "sleep 10"

	tok "nvme ns-rescan ${NVME_CHAR}"
	tok "nvme show-regs ${NVME_CHAR} -H"
	if [[ $MODEL =~ "SAMSUNG MZWLO1T9HCJR-00A07" ]]; then
		tok "nvme dir-receive ${NVME_CHAR} --dir-type 0 --dir-oper 1 --human-readable"
		tok "nvme dir-send ${NVME_DISK} --dir-type 0 --dir-oper 1 --target-dir 1 --endir 1"
	else
		tnot "nvme dir-receive ${NVME_CHAR} --dir-type 0 --dir-oper 1 --human-readable"
		tnot "nvme dir-send ${NVME_DISK} --dir-type 0 --dir-oper 1 --target-dir 1 --endir 1"
	fi
done
}

tlog "running $0"
trun "uname -a"
runtest
report_result
tend
