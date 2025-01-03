#!/bin/bash

TEST="kselftests"

[ ! "$RSTRNT_JOBID" ] && rm -rf logs && mkdir logs && export LOG_DIR="$PWD/logs"

if [ ! "$RSTRNT_JOBID" ]; then
	RED='\E[1;31m'
	GRN='\E[1;32m'
	# YEL='\E[1;33m'
	RES='\E[0m'
fi


rhel_major()
{
	source /etc/os-release
	echo $VERSION_ID | awk -F. '{print $1}'
}
rhel_minor()
{
	source /etc/os-release
	echo $VERSION_ID | awk -F. '{print $2}'
}

new_outputfile()
{
	[ "$RSTRNT_JOBID" ] && mktemp /mnt/testarea/tmp.XXXXXX || mktemp $LOG_DIR/tmp.XXXXXX
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

# set sysctl values and retore it back after testing
declare -A SYSCTL_ORIG
sysctl_set()
{
	local key=$1; shift
	local value=$1; shift

	SYSCTL_ORIG[$key]=$(sysctl -n $key)
	sysctl -qw $key="$value"
}

sysctl_restore()
{
	local key=$1; shift

	sysctl -qw $key="${SYSCTL_ORIG[$key]}"
}

log()
{
	echo -e "\n[$(date '+%T')][$(whoami)@$(uname -r | cut -f 2 -d-)]# " | tee -a $OUTPUTFILE
	echo -e "\n[  LOG: $1  ]" | tee -a $OUTPUTFILE
}

submit_log()
{
	for file in "$@"; do
		rlFileSubmit $file
	done
}

test_pass()
{
	let PASS++
	SCORE=${2:-$PASS}
	echo -e "\n:: [  PASS  ] :: Test '$1'" >> $OUTPUTFILE
	echo -e "::::::::::::::::"
	rlPass "Test '${TEST}/$1' PASS $SCORE"
	echo -e "::::::::::::::::\n"
}

test_fail()
{
	let FAIL++
	SCORE=${2:-$FAIL}
	echo -e ":: [  FAIL  ] :: Test '$1'" >> $OUTPUTFILE
	echo -e ":::::::::::::::::"
	rlFail "Test '${TEST}/$1' FAIL $SCORE"
	echo -e ":::::::::::::::::\n"
}

test_warn()
{
	let WARN++
	SCORE=${2:-$WARN}
	echo -e "\n:: [  WARN  ] :: Test '$1'" | tee -a $OUTPUTFILE
	echo -e "\n:::::::::::::::::"
	rlFail  "Test '${TEST}/$1' WARN $SCORE"
	echo -e ":::::::::::::::::\n"
}

test_skip()
{
	let SKIP++
	SCORE=${2:-$SKIP}
	echo -e "\n:: [  SKIP  ] :: Test '$1'" | tee -a $OUTPUTFILE
	echo -e "\n:::::::::::::::::"
	rlLog "Test '${TEST}/$1' SKIP $SCORE"
	echo -e ":::::::::::::::::\n"
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
	echo -e "\n[$(date '+%T')][$(whoami)@$(uname -r | cut -f 2 -d-)]# '$cmd'" | tee -a $OUTPUTFILE
	# FIXME: how should we handle if there are lots of output for the cmd,
	# and we only care the return value
	eval "$cmd" > >(tee -a $OUTPUTFILE)
	ret=$?
	if [ "$exp" -eq "$ret" ];then
		echo -e ":: [  ${GRN}PASS${RES}  ] :: Command '$cmd' (Expected $exp, got $ret, score $PASS)" | tee -a $OUTPUTFILE
		return 0
	else
		echo -e ":: [  ${RED}FAIL${RES}  ] :: Command '$cmd' (Expected $exp, got $ret, score $FAIL)" | tee -a $OUTPUTFILE
		return 1
	fi
}

# Usage: watch command timeout [signal]
watch()
{
	command=$1
	timeout=$2
	single=${3:-9}
	now=`date '+%s'`
	after=`date -d "$timeout seconds" '+%s'`

	eval "$command" &
	pid=$!
	while true; do
		now=`date '+%s'`

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
	local num=$1
	local total_num=$2
	local test_name=$3
	local test_result=$4

	if [ "${DEBUG_CMD}" ]; then
		log "Following are DEBUG commands output"
		run "${DEBUG_CMD}"
	fi

	if [ "$test_result" -eq 0 ]; then
		test_pass "${num}..${total_num} selftests: ${test_name} [PASS]"
	elif [ "$test_result" -eq $SKIP_CODE ]; then
		test_skip "${num}..${total_num} selftests: ${test_name} [SKIP]"
	elif [[ " $WAIVE_TARGETS " = *" ${test_name} "* ]]; then
		test_pass "${num}..${total_num} selftests: ${test_name} [WAIVE]"
	else
		test_fail "${num}..${total_num} selftests: ${test_name} [FAIL]"
	fi
}

# Check if expect test exist, return 0 if exist and 1 if not.
check_test_exist()
{
	local item=$1
	local folder

	folder=$(echo "$item" | cut -f1 -d':')

	# Check if the test in kselftest-list.txt and has it's own folder
	if grep -qE "$folder" "$EXEC_DIR"/kselftest-list.txt; then
		if [ -d "$EXEC_DIR/$folder" ]; then
			return 0
		fi
	fi

	# Special cases
	if [ "$item" == "default" ]; then
		return 0
	elif [ "$item" == "bpf_test_progs" ]; then
		if grep -q "bpf:test_progs" "$EXEC_DIR"/kselftest-list.txt; then
			if [ -f "$EXEC_DIR"/bpf/test_progs ]; then
				return 0
			fi
		fi
	fi

	return 1
}

if [ ! "$CKI_SELFTESTS_URL" ] && [ ! "$BUILD_FROM_SRC" ] && [ ! "$DELIVERED_TESTS" ]; then
	test_skip_exit "CKI_SELFTESTS_URL/BUILD_FROM_SRC/DELIVERED_TESTS not found. At least one must be set."
fi
