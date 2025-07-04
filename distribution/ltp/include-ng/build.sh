#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#

# workaround for https://github.com/teemtee/tmt/issues/3041
# tmt supports rstrnt-report-result
if [[ -z $RSTRNT_TASKNAME ]] && [[ -n $TMT_TEST_NAME ]]; then
	RSTRNT_TASKNAME="${TMT_TEST_NAME}"
fi

install_kirk()
{
	echo "============ Download kirk ============" | tee -a $OUTPUTFILE
	if ! rpm -q python3-click; then
		# install python3-click from epel
		source /etc/os-release
		rhel_x=$(echo $VERSION_ID | cut -d. -f1)
		pkg_mgr=$(command -v dnf &>/dev/null && echo dnf || echo yum)
		if [[ -e /run/ostree-booted ]]; then
			rpm-ostree -Ay --idempotent --allow-inactive install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${rhel_x}.noarch.rpm
			rpm-ostree -Ay --idempotent --allow-inactive install python3-click
		else
			$pkg_mgr -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${rhel_x}.noarch.rpm
			$pkg_mgr -y install python3-click
			$pkg_mgr -y remove epel-release
		fi
		if ! rpm -q python3-click; then
			rpm -q python3-pip > /dev/null || $pkg_mgr -y install python3-pip
			# install python3 click module from pip
			pip3 show click --quiet || pip3 install click
			if [ $? -ne 0 ]; then
				echo "Aborting current task: Couldn't install click" | tee -a $OUTPUTFILE
				if [[ -n $RSTRNT_TASKNAME ]]; then
					rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
					exit 0
				else
					exit 1
				fi
			fi
		fi
	fi

	KIRK_VER="${KIRK_VER:-v2.0}"
	KIRK_DIR="$(pwd)/kirk"

	[[ -d $KIRK_DIR ]] || git clone -b $KIRK_VER https://gitlab.com/redhat/centos-stream/tests/kernel/core/kirk --depth=10
	if [ $? -ne 0 ]; then
		echo "Aborting current task: Couldn't clone kirk" | tee -a $OUTPUTFILE
		if [[ -n $RSTRNT_TASKNAME ]]; then
			rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
			exit 0
		else
			exit 1
		fi
	fi

	cp -r "$KIRK_DIR" /mnt/testarea/
}

download_ltp()
{
	echo "============ Download LTP package ============" | tee -a $OUTPUTFILE
	if [ -z "$LTP_DOWNLOAD_URL" ]; then
		curl --fail --retry 5 -s -SLO https://github.com/linux-test-project/ltp/releases/download/${TESTVERSION}/ltp-full-${TESTVERSION}.tar.bz2
		if [ $? -ne 0 ]; then
			TARGET=ltp-$TESTVERSION
			curl --fail --retry 5 -s -SLO https://gitlab.com/redhat/centos-stream/tests/ltp/-/archive/$TESTVERSION/ltp-$TESTVERSION.tar.bz2
		fi
	elif echo $LTP_DOWNLOAD_URL | grep -E "tar.bz2"; then
		LTP_DOWNLOAD_URL=${LTP_DOWNLOAD_URL//TESTVERSION/"$TESTVERSION"}
		TARGET=$(basename $(echo $LTP_DOWNLOAD_URL | sed 's/\.tar\.bz2//'))
		curl --fail --retry 5 -s -SLO $LTP_DOWNLOAD_URL
	else
		TARGET=ltp-${TESTVERSION}
		curl --fail --retry 5 -s -SLO ${LTP_DOWNLOAD_URL}/${TESTVERSION}/ltp-${TESTVERSION}.tar.bz2
	fi
	if [ $? -ne 0 ]; then
		echo "upstream download failed, giving up" | tee -a $OUTPUTFILE
		echo "Aborting current task: Couldn't download LTP source." | tee -a $OUTPUTFILE
		if [[ -n $RSTRNT_TASKNAME ]]; then
			rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
			exit 0
		else
			exit 1
		fi
	fi

	rm -rf ${TARGET}

	echo "============ Unzip LTP package ============" | tee -a $OUTPUTFILE
	tar xjf ${TARGET}.tar.bz2 | tee -a $OUTPUTFILE

}

clone_ltp()
{
	TARGET=${PWD}/ltp
	rm -rf ${TARGET}
	git clone https://github.com/linux-test-project/ltp ${TARGET}
	if [ $? -ne 0 ]; then
		echo "Aborting current task: Couldn't clone LTP" | tee -a $OUTPUTFILE
		if [[ -n $RSTRNT_TASKNAME ]]; then
			rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
			exit 0
		else
			exit 1
		fi
	fi
	if [[ -n ${LTP_COMMIT_ID} && ${LTP_COMMIT_ID} != "latest" ]]; then
		git -C ${TARGET} checkout ${LTP_COMMIT_ID}
		if [ $? -ne 0 ]; then
			echo "Aborting current task: Couldn't checkout ${LTP_COMMIT_ID}" | tee -a $OUTPUTFILE
			if [[ -n $RSTRNT_TASKNAME ]]; then
				rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
				exit 0
			else
				exit 1
			fi
		fi
	fi
	if [[ -z ${LTP_COMMIT_ID} || ${LTP_COMMIT_ID} == "latest" ]]; then
		LTP_COMMIT_ID=$(git -C ${TARGET} log --format="%H" -n 1)
	fi
	TESTVERSION="commit-${LTP_COMMIT_ID}"
}

configure()
{
	#Patch-inc
	echo "============ Patch patch_inc_tolerant ==============" | tee -a $OUTPUTFILE
	patch_inc > patchinc.log 2>&1
	cat patchinc.log | tee -a $OUTPUTFILE

	echo "============ Start LTP configure ============" | tee -a $OUTPUTFILE
	AUTOCONFIGVER=$(rpm -qa autoconf |cut -f 2 -d "-")
	# AUTOMAKEVER=$(rpm -qa automake |cut -f 2 -d "-"|cut -f 1,2 -d ".")
	AUTOCONFIGVER_1=$(echo $AUTOCONFIGVER |cut -f 1 -d ".")
	AUTOCONFIGVER_2=$(echo $AUTOCONFIGVER |cut -f 2 -d ".")
	DOWNLOAD_URL=$(echo ${LOOKASIDE:-http:\/\/download.devel.redhat.com\/qa\/rhts\/lookaside\/})
	if [[ $AUTOCONFIGVER_1 -lt 1 || $AUTOCONFIGVER_1 -eq 2 && $AUTOCONFIGVER_2 -lt 69 ]]; then \
		wget -q $DOWNLOAD_URL/m4-1.4.16.tar.gz ; \
		tar xzf m4-1.4.16.tar.gz; \
		pushd  m4-1.4.16; \
		./configure --prefix=/usr > /dev/null 2>&1; \
		make > /dev/null 2>&1 && make install > /dev/null 2>&1; \
		popd ; \
		wget -q $DOWNLOAD_URL/autoconf-2.69.tar.gz ; \
		tar xzf autoconf-2.69.tar.gz; \
		pushd autoconf-2.69; \
		./configure --prefix=/usr > /dev/null 2>&1 ; \
		make > /dev/null 2>&1 && make install > /dev/null 2>&1; \
		popd ; \
	fi
	pushd ${TARGET}; make autotools; ./configure --prefix=${TARGET_DIR} &> configlog.txt || cat configlog.txt; popd
}

build_all()
{
	setup_testarea
	if [[ "y" == "${USE_LTP_RPM}" ]]; then
		dnf copr -y enable pifang/ltp
		if dnf repoquery --available --queryformat '%{version}-%{release}' ltp | grep "${TESTVERSION}"; then
			echo "============ Install LTP-${TESTVERSION} rpm ============" | tee -a $OUTPUTFILE
			dnf install -y ltp-${TESTVERSION}
			if [ $? -ne 0 ]; then
				echo "Aborting current task: Couldn't install LTP rpm." | tee -a $OUTPUTFILE
				if [[ -n $RSTRNT_TASKNAME ]]; then
					rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
					exit 0
				else
					exit 1
				fi
			fi
		else
			echo "============ USE_LTP_RPM is set, but version ${TESTVERSION} is not build in copr ============" | tee -a $OUTPUTFILE
			echo "============ Install LTP-${TESTVERSION} from source ============" | tee -a $OUTPUTFILE
			download_ltp
		fi
	elif [[ -z ${LTP_COMMIT_ID} ]]; then
		download_ltp
	else
		clone_ltp
		if [[ -f ${TARGET_DIR}/runltp ]] && grep -q "${TESTVERSION}" ${TARGET_DIR}/ltp_version; then
			# the LTP_COMMIT_ID is already the version installed
			return
		fi
		# generate RHELKT1LITE.next
		echo "Going to generate RHELKT1LITE.next"
		pushd ../lite/configs
		# restraint doesn't seem to keep the file permission
		chmod +x ./config-maker.sh
		LTP_VERSION=next ./config-maker.sh &> config-maker.txt
		if [ $? -ne 0 ]; then
			cat config-maker.txt
			echo "Aborting current task: Couldn't generate test config." | tee -a $OUTPUTFILE
			if [[ -n $RSTRNT_TASKNAME ]]; then
				rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
				exit 0
			else
				exit 1
			fi
		fi
		popd
		echo "RHELKT1LITE.next is generated"
	fi

	install_kirk
	if [[ "y" == "${USE_LTP_RPM}" ]] && rpm -q "ltp-${TESTVERSION}"; then
		return
	fi

	configure
	echo "============ Start ${MAKE} and install LTP ============" | tee -a $OUTPUTFILE
	timeout_value=${LTP_BUILD_TIMEOUT_M:-30}
	if uname -r | grep -q 'debug'; then
		timeout_value=${LTP_BUILD_TIMEOUT_M:-90}
	fi
	res="PASSED"
	timeout "${timeout_value}m" ${MAKE} -C ${TARGET} all &> buildlog.txt
	build_res=$?
	if [ ${build_res} -eq 124 ]; then
		echo "Cleaning up ${TARGET_DIR}"
		rm -rf ${TARGET_DIR}
		if [[ -n $RSTRNT_TASKNAME ]]; then
			rstrnt-report-result "build_all build timeout" WARN
			exit 0
		else
			exit 1
		fi
	fi
	if [ ${build_res} -ne 0 ]; then
		res="FAILED"
		SubmitLog ./buildlog.txt
		if [[ -n $RSTRNT_TASKNAME ]]; then
			rstrnt-report-result "build_all build failed" WARN
			exit 0
		else
			exit 1
		fi
	fi
	echo "============ ${MAKE} -C ${TARGET} all: ${res}  ============" | tee -a $OUTPUTFILE
	res="PASSED"
	${MAKE} -C ${TARGET} install &> buildlog.txt
	if [ $? -ne 0 ]; then
		res="FAILED"
	fi
	echo "============ ${MAKE} -C ${TARGET} install: ${res}  ============" | tee -a $OUTPUTFILE
	SubmitLog ./buildlog.txt
	if [[ ${res} == "PASSED" ]]; then
		echo "${TESTVERSION}" > ${TARGET_DIR}/ltp_version
	else
		if [[ -n $RSTRNT_TASKNAME ]]; then
			rstrnt-report-result "build_all failed" WARN
			exit 0
		else
			exit 1
		fi
	fi
}
