#!/bin/bash

# Enable TMT testing for RHIVOS
auto_include=../../../automotive/include/rhivos.sh
[ -f $auto_include ] && . $auto_include
declare -F kernel_automotive && kernel_automotive && is_rhivos=1 || is_rhivos=0

if ! (($is_rhivos)); then
    # Include rhts environment
    . /usr/bin/rhts-environment.sh
fi

. /usr/share/beakerlib/beakerlib.sh || exit 1

# source fwts include/library
. ../include/runtest.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        fwtsSetup
    rlPhaseEnd

    rlPhaseStartTest BIOSInfo
        LOGFILE=biosinfo.log
        rlLog "Gathering BIOS information, saving to $LOGFILE"
        rlRun "fwts acpiinfo bios_info dmicheck mcfg cmosdump crsdump ebdadump memmapdump mpdump --results-output=$LOGFILE" 0,1 "run fwts tests for BIOS info."
        rlFileSubmit $LOGFILE
    rlPhaseEnd #ROMInfo
    rlPhaseStartTest ROMInfo
        LOGFILE=romdump.log
        rlLog "Gathering ROM information, saving to $LOGFILE"
        rlRun "fwts romdump --results-output=$LOGFILE" 0,1 "run fwts tests for ROM info."
        rlFileSubmit $LOGFILE
    rlPhaseEnd #ROMInfo
    rlPhaseStartTest UEFIInfo
        LOGFILE=uefidump.log
        rlLog "Dumping UEFI configuration, saving to $LOGFILE"
        rlRun "fwts uefidump --results-output=$LOGFILE" 0,1 "run fwts tests for ROM info."
        rlFileSubmit $LOGFILE
        LOGFILE=uefivarinfo.log
        rlLog "Dumping UEFI variable data, saving to $LOGFILE"
        rlRun "fwts uefivarinfo --results-output=$LOGFILE" 0,1 "run fwts tests for ROM info."
        rlFileSubmit $LOGFILE
    rlPhaseEnd #UEFIInfo
    rlPhaseStartTest SYSTEMInfo
        LOGFILE=""
        rlLog "Gathering ACPI, dmesg, dmidecode, lspci information."
        # The default lspci path does not match RHEL or Fedora, so we override it.
        rlRun "fwts --dump --lspci=/sbin/lspci" 0,1 "run fwts --dump"
        rlRun -l "cat README.txt" 0
        rlFileSubmit acpidump.log
        rlFileSubmit dmesg.log
        rlFileSubmit dmidecode.log
        rlFileSubmit lspci.log
    rlPhaseEnd #SYSTEMInfo
    rlPhaseStartCleanup
        fwtsCleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
