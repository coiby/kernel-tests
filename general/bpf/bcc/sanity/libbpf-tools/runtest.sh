#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh
. denylist.sh

BCC_TOOLS_ENABLE_DENYLIST=${BCC_TOOLS_ENABLE_DENYLIST:-*}

function waive_fails()
{
	local arch="$1"; shift
	local kernel_version="$1"; shift
	local tool="$@"

	for fail in "${DENYLIST[@]}"
	do
		set -- $fail
		local denylist_result=$1; shift
		local denylist_arch=$1; shift
		local denylist_kernel_version_start=$1; shift
		local denylist_kernel_version_end=$1; shift
		local denylist_tool="$@"

		grep -q "$arch," <<<"$denylist_arch" || continue
		grep -q "$tool" <<<"$denylist_tool" || continue
		# K_Vercmp $kernel_version $denylist_kernel_version_start
		# [[ $K_KVERCMP_RET -ge "0" ]] || continue
		# K_Vercmp $kernel_version $denylist_kernel_version_start
		# [[ $K_KVERCMP_RET -lt "0" ]] || continue
		return 0
	done
	return 1
}

function test_setup()
{
    if ! grep "CONFIG_BPF_SYSCALL=y" /boot/config-$(uname -r) ; then
        rstrnt-report-result "CONFIG_BPF_SYSCALL_disabled" SKIP
        rlPhaseEnd
        exit 0
    fi
    rpm -q libbpf-tools || dnf install -y libbpf-tools
    if ! rpm -q libbpf-tools ; then
        rstrnt-report-result "libbpf-tools does not exist" SKIP
        rlPhaseEnd
        exit 0
    fi
    rlPhaseStartSetup
    # required by gethostlatency (to provide libc.so)
    rlRun "dnf install -y glibc-devel"
    modprobe ext4
    modprobe nfs
    modprobe xfs
    rm libbpf-tools-result.txt -f
    rlPhaseEnd

}
function test_cleanup()
{
    rlPhaseStartCleanup
        rlFileSubmit libbpf-tools-result.txt
        grep -v PASS libbpf-tools-result.txt
    rlPhaseEnd
}

# This is now a placeholder. The known issue checker should be implemented in a
# more configurable way in this function.
function SkipTest ()
{
    cmd_file=$1
    virt_status=$(systemd-detect-virt)
    if [[ "${cmd_file}" == "bpf-cpufreq" ]] && [[ "${virt_status}" != "none" ]]  ; then
        return 0
    fi
    if [[ "${cmd_file}" == *"btrfs"* ]] ; then
        return 0
    fi
    return 1
}

rlJournalStart

test_setup

for cmd in $(rpm -ql libbpf-tools| grep bin | awk -F '/' '{print $NF}') ; do
    SkipTest $cmd
    if [ $? == 0 ]; then
        echo "$cmd Skipped" | tee -a libbpf-tools-result.txt
        rstrnt-report-result "$cmd Skipped" SKIP
        continue
    fi
    rlPhaseStartTest "${cmd}"
    case "${cmd}" in
        *nfs*)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -t nfs
             ;;
        *ext4*)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -t ext4
             ;;
        *xfs*)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -t xfs
             ;;
        bpf-fsslower|bpf-fsdist)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -t xfs
             ;;
        bpf-ksnoop)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd trace ip_send_skb
             ;;
        bpf-vfsstat)
             timeout --preserve-status --signal=SIGINT -k 20s 20s $cmd 3 3
             ;;
        bpf-funclatency)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd vfs_read
             ;;
        bpf-gethostlatency)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -l /usr/lib64/libc.so.6
             ;;
        *)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd
            ;;
    esac
    retcode=$?
    if [ $retcode == 0 ] ; then
        echo "$cmd PASS" | tee -a libbpf-tools-result.txt
        rlPass "$cmd"
    else
        if [[ "${BCC_TOOLS_ENABLE_DENYLIST}" == "y" ]]; then
            rlLog "LIBBPF TOOLS DENYLIST ENABLED (known fails will be hidden)"
            if waive_fails "$(uname -m)" "$(uname -r)" "$cmd"; then
                rlPass "Command $cmd failed but was waived as a known issue."
            else
                echo "$cmd FAILED with $retcode"  | tee -a libbpf-tools-result.txt
                rlFail "$cmd FAILED with $retcode"
            fi
        else
            echo "$cmd FAILED with $retcode"  | tee -a libbpf-tools-result.txt
            rlFail "$cmd FAILED with $retcode"
        fi
    fi
    rlPhaseEnd
done

test_cleanup

rlJournalPrintText
rlJournalEnd

