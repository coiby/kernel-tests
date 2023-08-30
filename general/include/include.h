#!/bin/bash

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
    if rpm -q "kernel-automotive-$(uname -r)" > /dev/null 2>&1; then
       return  0
    fi
    return 1
}

install_repos()
{
    kcomp=${COMPOSE} #To create the right repo links later and grab certain packages. not used on automotive builds.
    id=$(grep ^ID= /etc/os-release | cut -d = -f 2) #Information about what os we are on, rhel or centos
    major=$(grep ^VERSION_ID= /etc/os-release | cut -d = -f 2 | cut -d \" -f 2 | cut -d . -f 1) #Main release e.g. 9
    karch=$(uname -m)

    if kernel_automotive; then
        sed -i "s/\$stream/9-stream/" /etc/yum.repos.d/centos*.repo
        dnf install 'dnf-command(config-manager)' -y
        dnf config-manager --set-enabled crb
        dnf config-manager --add-repo https://buildlogs.centos.org/${major}-stream/automotive/${karch}/packages-main
        dnf config-manager --add-repo https://buildlogs.centos.org/${major}-stream/automotive/${karch}/packages-main/debug
        dnf config-manager --add-repo https://buildlogs.centos.org/${major}-stream/autosd/${karch}/packages-main
        dnf config-manager --add-repo https://buildlogs.centos.org/${major}-stream/autosd/${karch}/packages-main/debug
        sed -i '$ a gpgcheck=0' /etc/yum.repos.d/buildlogs.centos.org_${major}-stream_automotive_${karch}_packages-main.repo
        sed -i '$ a gpgcheck=0' /etc/yum.repos.d/buildlogs.centos.org_${major}-stream_automotive_${karch}_packages-main_debug.repo
        sed -i '$ a gpgcheck=0' /etc/yum.repos.d/buildlogs.centos.org_${major}-stream_autosd_${karch}_packages-main.repo
        sed -i '$ a gpgcheck=0' /etc/yum.repos.d/buildlogs.centos.org_${major}-stream_autosd_${karch}_packages-main_debug.repo
    fi
}
