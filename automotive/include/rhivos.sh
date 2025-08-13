#!/bin/bash

# shellcheck disable=all
# Disabling all shellcheck warnings to allow the merge request, as this script is scheduled for deprecation

[ ! "$RSTRNT_JOBID" ] && rm -rf logs && mkdir logs && export TMPDIR="$PWD/logs"

if [ ! "$RSTRNT_JOBID" ]; then
    RED='\E[1;31m'
    GRN='\E[1;32m'
    YEL='\E[1;33m'
    RES='\E[0m'
fi

[ ! "$RSTRNT_JOBID" ] && rm -rf /mnt/testarea && mkdir /mnt/testarea && export TESTAREA="/mnt/testarea"

new_outputfile()
{
    [ "$RSTRNT_JOBID" ] && mktemp /mnt/testarea/tmp.XXXXXX || mktemp $TMPDIR/tmp.XXXXXX
}

setup_env()
{
    # install dependence
    # save testing environment
    # export our new variable
    export PASS=0
    export FAIL=0
    export WARN=0
    export SKIP=0
    export OUTPUTFILE=$(new_outputfile)
}

clean_env()
{
    # clean environment
    # restore environment
    unset PASS
    unset FAIL
    unset WARN
    unset SKIP
}

log()
{
    echo -e "\n[$(date '+%T')][$(whoami)@$(uname -r | cut -f 2 -d-)]# " | tee -a $OUTPUTFILE
    echo -e "\n[  LOG: $1  ]" | tee -a $OUTPUTFILE
}

submit_log()
{
    for file in "$@"; do
        [ "$RSTRNT_JOBID" ] && rstrnt-report-log -l $file || echo $file
    done
}

test_pass()
{
    let PASS++
    SCORE=${2:-$PASS}
    echo -e "\n:: [  PASS  ] :: Test '"$1"'" >> $OUTPUTFILE
    if [ $RSTRNT_JOBID ]; then
        rstrnt-report-result "${TEST}/$1" "PASS" "$SCORE"
    else
        echo -e "::::::::::::::::"
        echo -e ":: [  ${GRN}PASS${RES}  ] :: Test '"${TEST}/$1"'"
        echo -e "::::::::::::::::\n"
    fi
}

test_fail()
{
    let FAIL++
    SCORE=${2:-$FAIL}
    echo -e ":: [  FAIL  ] :: Test '"$1"'" >> $OUTPUTFILE
    if [ $RSTRNT_JOBID ]; then
        rstrnt-report-result "${TEST}/$1" "FAIL" "$SCORE"
    else
        echo -e ":::::::::::::::::"
        echo -e ":: [  ${RED}FAIL${RES}  ] :: Test '"${TEST}/$1"' FAIL $SCORE"
        echo -e ":::::::::::::::::\n"
    fi
}

test_warn()
{
    let WARN++
    SCORE=${2:-$WARN}
    echo -e "\n:: [  WARN  ] :: Test '"$1"'" | tee -a $OUTPUTFILE
    if [ $RSTRNT_JOBID ]; then
        rstrnt-report-result "${TEST}/$1" "WARN" "$SCORE"
    else
        echo -e "\n:::::::::::::::::"
        echo -e ":: [  ${YEL}WARN${RES}  ] :: Test '"${TEST}/$1"'"
        echo -e ":::::::::::::::::\n"
    fi
}

test_skip()
{
    let SKIP++
    SCORE=${2:-$SKIP}
    echo -e "\n:: [  SKIP  ] :: Test '"$1"'" | tee -a $OUTPUTFILE
    if [ $RSTRNT_JOBID ]; then
        rstrnt-report-result "${TEST}/$1" "SKIP" "$SCORE"
    else
        echo -e "\n:::::::::::::::::"
        echo -e ":: [  ${YEL}SKIP${RES}  ] :: Test '"${TEST}/$1"'"
        echo -e ":::::::::::::::::\n"
    fi
}

test_pass_exit()
{
    test_pass "$@"
    clean_env
    exit 0
}

test_fail_exit()
{
    test_fail "$@"
    clean_env
    exit 1
}

test_warn_exit()
{
    test_warn "$@"
    clean_env
    exit 1
}

test_skip_exit()
{
    test_skip "$@"
    clean_env
    exit 0
}

# Usage: run command [return_value]
run()
{
    cmd=$1
    # FIXME: only support zero or none zero, doesn't support 2-10, or 2,3,4
    exp=${2:-0}
    echo -e "\n[$(date '+%T')][$(whoami)@$(uname -r | cut -f 2 -d-)]# '"$cmd"'" | tee -a $OUTPUTFILE
    # FIXME: how should we handle if there are lots of output for the cmd,
    # and we only care the return value
    eval "$cmd" > >(tee -a $OUTPUTFILE)
    ret=$?
    if [ "$exp" -eq "$ret" ];then
        echo -e ":: [  ${GRN}PASS${RES}  ] :: Command '"$cmd"' (Expected $exp, got $ret, score $PASS)" | tee -a $OUTPUTFILE
        return 0
    else
        echo -e ":: [  ${RED}FAIL${RES}  ] :: Command '"$cmd"' (Expected $exp, got $ret, score $FAIL)" | tee -a $OUTPUTFILE
        return 1
    fi
}

# Usage: watch command timeout [signal]
watch()
{
    command=$1
    timeout=$2
    single=${3:-9}
    now=$(date '+%s')
    after=$(date -d "$timeout seconds" '+%s')

    eval "$command" &
    pid=$!
    while true; do
        now=$(date '+%s')

        if ps -p $pid; then
            if [ "$after" -gt "$now" ]; then
                sleep 10
            else
                log "command (# $command) still alive, kill it"
                kill -$single $pid
                break
            fi
        else
            log "command (# $command) exit itself"
            break
        fi
    done
}

check_skip()
{
    [[ " $SKIP_TARGETS " = *" $1 "* ]] && return 0 || return 1
}

check_result()
{
    local test_name=$1
    local test_result=$2

    if [ "$test_result" == "PASS" ]; then
        test_pass "${test_name} [PASS]"
    elif [ "$test_result" == "SKIP" ]; then
        test_skip "${test_name} [SKIP]"
    elif [ "$test_result" == "WARN" ]; then
        test_pass "${test_name} [WARN]"
    else
        test_fail "${test_name} [FAIL]"
    fi
}

# return 0 when running kernel rt
kernel_rt()
{
    if [[ $(uname -r) =~ "rt" ]]; then
       return  0
    fi
    return 1
}


# return 0 when running kernel debug
kernel_debug()
{
    if [[ $(uname -r) =~ "debug" ]]; then
       return  0
    fi
    return 1
}

# return 0 when running kernel automotive
kernel_automotive()
{
    if (uname -r | grep -w -q el[0-9].*iv); then
       return  0
    fi
    return 1
}

# return 0 when running in ostree environment
system_ostree() {
  if [[ -e /run/ostree-booted ]]; then
    return 0
  fi
  return 1
}

install_repos()
{
    id=$(grep ^ID= /etc/os-release | cut -d = -f 2)
    major=$(grep ^VERSION_ID= /etc/os-release | cut -d = -f 2 | cut -d \" -f 2 | cut -d . -f 1)
    karch=$(arch)

    if kernel_automotive; then
        if [[ ${id} =~ "rhel" ]]; then
            if ! ls /etc/yum.repos.d/rhel.repo > /dev/null 2>&1; then
                touch /etc/yum.repos.d/rhel.repo
cat << 'EOF' >> /etc/yum.repos.d/rhel.repo
[baseos-rhel]
baseurl=http://download.devel.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/BaseOS/$basearch/os
enabled=1
gpgcheck=0
[appstream-rhel]
baseurl=http://download.devel.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/AppStream/$basearch/os/
enabled=1
gpgcheck=0
[crb-rhel]
baseurl=http://download.devel.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/CRB/$basearch/os/
enabled=1
gpgcheck=0
[baseos-debug-rhel]
baseurl=http://download.devel.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/BaseOS/$basearch/debug/tree
enabled=1
gpgcheck=0
[appstream-debug-rhel]
baseurl=http://download.devel.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/AppStream/$basearch/debug/tree
enabled=1
gpgcheck=0
[crb-debug-rhel]
baseurl=http://download.devel.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/CRB/$basearch/debug/tree
enabled=1
gpgcheck=0
EOF
            fi
            if ! rpm -q dnf-plugins-core > /dev/null 2>&1; then
                if stat /run/ostree-booted > /dev/null 2>&1; then
                    rpm-ostree -A --idempotent --allow-inactive install 'dnf-command(config-manager)'
                else
                    dnf install 'dnf-command(config-manager)' -y
                fi
            fi
            local compose=$(echo $(uname -r) | sed -e "s/+debug//" -e "s/.$(arch)//")
            if ! ls /etc/yum.repos.d/kernel-automotive-${compose}.repo > /dev/null 2>&1; then
                echo " + Install rhivos brew repository"
                local version=$(echo ${compose} | cut -d "-" -f 1)
                local release=$(echo ${compose} | cut -d "-" -f 2)
                curl -L http://brew-task-repos.usersys.redhat.com/repos/official/kernel-automotive/${version}/${release}/kernel-automotive-${compose}.repo -o /etc/yum.repos.d/kernel-automotive-${compose}.repo
            fi
        else
            sed -i "s/\$stream/9-stream/" /etc/yum.repos.d/centos*.repo
            if ! rpm -q dnf-plugins-core > /dev/null 2>&1; then
                if stat /run/ostree-booted > /dev/null 2>&1; then
                    rpm-ostree -A --idempotent --allow-inactive install 'dnf-command(config-manager)'
                else
                    dnf install 'dnf-command(config-manager)' -y
                fi
            fi
            dnf config-manager --set-enabled crb
            if ! ls /etc/yum.repos.d/*buildlogs* > /dev/null 2>&1 && ! ls /etc/yum.repos.d/*distro* > /dev/null 2>&1; then
                dnf config-manager --add-repo https://buildlogs.centos.org/${major}-stream/autosd/${karch}/packages-main
                dnf config-manager --add-repo https://buildlogs.centos.org/${major}-stream/autosd/${karch}/packages-main/debug
                dnf config-manager --add-repo https://buildlogs.centos.org/${major}-stream/automotive/${karch}/packages-main
                dnf config-manager --add-repo https://buildlogs.centos.org/${major}-stream/automotive/${karch}/packages-main/debug
                sed -i '$ a gpgcheck=0' /etc/yum.repos.d/buildlogs.centos.org_${major}-stream_autosd_${karch}_packages-main.repo
                sed -i '$ a gpgcheck=0' /etc/yum.repos.d/buildlogs.centos.org_${major}-stream_autosd_${karch}_packages-main_debug.repo
                sed -i '$ a gpgcheck=0' /etc/yum.repos.d/buildlogs.centos.org_${major}-stream_automotive_${karch}_packages-main.repo
                sed -i '$ a gpgcheck=0' /etc/yum.repos.d/buildlogs.centos.org_${major}-stream_automotive_${karch}_packages-main_debug.repo
            fi
        fi
        if ! ls /etc/yum.repos.d/*epel* > /dev/null 2>&1; then
            if stat /run/ostree-booted > /dev/null 2>&1; then
                rpm-ostree -A --idempotent --allow-inactive install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major}.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-${major}.noarch.rpm
            else
                dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major}.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-${major}.noarch.rpm -y
            fi
        fi
    fi
}

install_kernel_automotive_devel()
{
    if stat /run/ostree-booted > /dev/null 2>&1; then
        rpm-ostree -A --idempotent --allow-inactive install kernel-automotive-devel-$(uname -r)
    else
        dnf install -y kernel-automotive-devel-$(uname -r)
    fi
}

install_kernel_automotive_source() {
  local KVer=$(uname -r | awk -F '-' '{print $1}')
  local KDIST=$(uname -r | sed "s/.$(arch)//g;s/\+debug//g" | awk -F '.' '{print "."$NF}')
  local KBuild=$(uname -r | awk -F '-' '{print $2}' | sed "s/.$(arch)//g;s/\+debug//g" | sed "s/${KDIST}//g")
  local KBuildPrefix=$(echo ${KBuild} | awk -F '.' '{print $1}')

  # $ uname -r
  # 5.14.0-163.125.el9iv.aarch64
  # ^^^^^^               KVer (5.14.0)
  #        ^^^           KBuildPrefix (163)
  #        ^^^^^^        KBuild (163.125)
  #                ^^^^^ KDIST (el9iv)

  local kernel_name=kernel-automotive-${KVer}-${KBuild}${KDIST}

  dnf download ${kernel_name} --source || {
    # Workaround: RHIVOS doesn't offer the source code through dnf repos at this moment
    type wget || install_packages wget
    wget --no-check-certificate https://cbs.centos.org/kojifiles/packages/kernel-automotive/${KVer}/${KBuild}${KDIST}/src/${kernel_name}.src.rpm
  }

  if system_ostree; then
    rpm-ostree install --apply-live --idempotent --allow-inactive -y ${kernel_name}.src.rpm || {
      # Workaround: rpm-ostree doesn't support installing source code rpms
      rpm -ivh --force ${kernel_name}.src.rpm
    }
  else
    # Workaround: `dnf localinstall -y ${kernel_name}.src.rpm`
    # results in "Error: Will not install a source rpm package"
    rpm -ivh --force ${kernel_name}.src.rpm
  fi

  if [[ -f /usr/src/kernels/$(uname -r)/Kconfig ]]; then
    echo "The source code for ${kernel_name} has been installed."
    return 0
  else
    echo "Failed to install the source code for ${kernel_name}."
    return 1
  fi
}
