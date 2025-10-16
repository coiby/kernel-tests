#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh
. denylist.sh

LOGDIR=$(mktemp -d)
LIBBPF_TOOLS_ENABLE_DENYLIST=${LIBBPF_TOOLS_ENABLE_DENYLIST:-*}

# K_Vercmp() returns one of the following values in the global K_KVERCMP_RET:
#   -1 if kernel version from argument $1 is older
#    0 if kernel version from argument $1 is the same as $2
#    1 if kernel version from argument $1 is newer
K_KVERCMP_RET=0
function K_Vercmp ()
{
        if [[ "$1" == "$2" ]]; then
                K_KVERCMP_RET=0
        else
                local sorted_versions=$(printf "%s\n%s" "$1" "$2" | sort -V)
                local first_sorted_version=$(echo "$sorted_versions" | head -n 1)
                if [[ "$first_sorted_version" == "$1" ]]; then
                        K_KVERCMP_RET=-1
                else
                        K_KVERCMP_RET=1
                fi
        fi
}

function waive_fails()
{
    local rhel_version="$1"; shift
    local arch="$1"; shift
    local libbpf_tools_version="$1"; shift
    local tool="$1"; shift
    local log="$1"

    local fail denylist_status denylist_rhel_version denylist_arch denylist_libbpf_tools_version_start denylist_libbpf_tools_version_end denylist_tool delylist_keywords denylist_jira

    for fail in "${DENYLIST[@]}"
    do
        IFS='|' read -r denylist_status denylist_rhel_version denylist_arch denylist_libbpf_tools_version_start denylist_libbpf_tools_version_end denylist_tool delylist_keywords denylist_jira<<< "$fail"
        true "${denylist_status}" "${denylist_jira}"
        if [[ "$tool" != "$denylist_tool" ]]; then
                continue
        fi
        if [[ "$rhel_version" != "$denylist_rhel_version" ]]; then
                continue
        fi
        if [[ "${arch}" != "${denylist_arch}" ]]; then
                continue
        fi
        K_Vercmp $libbpf_tools_version $denylist_libbpf_tools_version_start
        if [ "${K_KVERCMP_RET}" -eq -1 ]; then
                continue
        fi
        K_Vercmp $libbpf_tools_version $denylist_libbpf_tools_version_end
        if [ "${K_KVERCMP_RET}" -ge 0 ]; then
                continue
        fi
        if grep -qF "${delylist_keywords}" "${log}"; then
                return 0
        else
                continue
        fi
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

ARCH=$(uname -m)
LIBBPF_TOOLS_VERSION=$(rpm -q libbpf-tools | cut -d '-' -f 3)
RHEL_VERSION=$(echo "RHEL-$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1)")

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
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -t nfs 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
             ;;
        *ext4*)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -t ext4 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
             ;;
        *xfs*)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -t xfs 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
             ;;
        bpf-fsslower|bpf-fsdist)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -t xfs 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
             ;;
        bpf-ksnoop)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd trace ip_send_skb 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
             ;;
        bpf-vfsstat)
             timeout --preserve-status --signal=SIGINT -k 20s 20s $cmd 3 3 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
             ;;
        bpf-funclatency)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd vfs_read 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
             ;;
        bpf-gethostlatency)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd -l /usr/lib64/libc.so.6 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
             ;;
        *)
             timeout --preserve-status --signal=SIGINT -k 5s 5s $cmd 2>&1 \
                        | tee -a ${LOGDIR}/${tool}.out
            ;;
    esac
    retcode=$?
    if [ $retcode == 0 ] ; then
        echo "$cmd PASS" | tee -a libbpf-tools-result.txt
        rlPass "$cmd"
    else
        if [[ "${LIBBPF_TOOLS_ENABLE_DENYLIST}" == "y" ]]; then
            rlLog "LIBBPF TOOLS DENYLIST ENABLED (known fails will be hidden)"
            if waive_fails "${RHEL_VERSION}" "${ARCH}" "${LIBBPF_TOOLS_VERSION}" "${tool}" "${LOGDIR}/${tool}.out"; then
                echo "$cmd FAILED with $retcode but was waived as a known issue." | tee -a libbpf-tools-result.txt
                rlPass "$cmd"
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

