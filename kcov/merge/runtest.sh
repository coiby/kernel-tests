#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/kcov/merge
#   Description: Merge /kernel/kcov/finalize data
#   Author: Jing Yang <jinyang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh
. /usr/share/beakerlib/beakerlib.sh
. ../include/include.sh

PACKAGE="merge"

TEST="/kcov/merge"

#ssl certificate
curl -s https://password.corp.redhat.com/RH-IT-Root-CA.crt -o /etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt
curl -s https://password.corp.redhat.com/legacy.crt -o /etc/pki/ca-trust/source/anchors/legacy.crt
update-ca-trust

setup_beaker_client_repo()
{
	local repo_url=http://download.lab.bos.redhat.com/beakerrepos/beaker-client-RedHatEnterpriseLinux.repo
	wget $repo_url -O /etc/yum.repos.d/beaker-client.repo
	sed -i '/enabled=/ a sslverify=false' /etc/yum.repos.d/beaker-client.repo
	return $?
}

setup_beaker_client_conf()
{
	cat > /etc/beaker/client.conf <<'EOF'
# Base URL of the Beaker server (without trailing slash!)
HUB_URL = "https://beaker.engineering.redhat.com"

# Hub authentication method
AUTH_METHOD = "krbv"
#AUTH_METHOD = "password"

# Username and password
#USERNAME = ""
#PASSWORD = ""

# Kerberos principal. If commented, default principal obtained by kinit is used.
#KRB_PRINCIPAL = "host/$HOSTNAME"

# Kerberos keytab file.
#KRB_KEYTAB = "/etc/krb5.keytab"

# Kerberos service prefix. Example: host, HTTP
#KRB_SERVICE = "HTTP"

# Kerberos realm. If commented, last two parts of domain name are used. Example: MYDOMAIN.COM.
KRB_REALM = "REDHAT.COM"

# Kerberos credential cache file.
#KRB_CCACHE = ""

# SSL CA certificate to verify the Beaker server's SSL certificate.
# By default, uses the system-wide CA certificate bundle.
#CA_CERT = "/etc/beaker/RedHatInternalCA.pem"
EOF
}

download_kcov() {
	local tgz_prefix=kcov_all-J:
	local taskkey='id="[0-9]+" name="/kernel/kcov/finalize"'

	[ $# -lt 1 ] && {
		echo "Usage: $0 <J:jobid> [J:jobid ....]"
		return 1
	}
	echo "Job list: $*"

	if ! rpm -q beaker-client >/dev/null; then
		setup_beaker_client_repo || {
			echo "{Err} failed to setup beaker-client repo"
			return 1
		}
		yum install -y beaker-client
		setup_beaker_client_conf
	fi
	which bkr || {
		echo "{Err} /bin/bkr not find, you must install pkg beaker-client first."
		return 1
	}

	rm -rf $TGZDIR_NAME && mkdir -p $TGZDIR_NAME
	rm -rf $INFO_DIR && mkdir -p $INFO_DIR

	for job in "$@"; do
		echo "{Info}-------------current Job $job-----------------"
		# skip invalid jobID
		echo $job|grep -q '^J:[0-9]' || {
			echo "{Warn} invalid jobID: $job (should be J:[0-9]+)"
			continue
		}

		# Get kcov/finalize task ids of the Job
		bkr job-results --prettyxml $job >$job.res.xml ||
			report_result "job-results-$job" "FAIL"

		# Generate test case list from Job result if $GENCASELIST is set to YES
		grep "<task avg_time=" $job.res.xml |
			egrep -v 'name="(/kernel/kcov|/distribution)/' |
			awk -F'[ ="]+' '{printf("%s\n\t%s %s\n", $9, $11, $13)}' |
			sed '/^[^ |\t]/s#[^0-9a-zA-Z_]#_#g' >>$KCOV_TEST_LIST

		taskIdList=$(grep -Pio 'name="/kernel/kcov/finalize".*id="\K[^"]*' $job.res.xml | xargs)
		[ -z "$taskIdList" ] && taskIdList=$(egrep -o "$taskkey" $job.res.xml | egrep -o '[0-9]+' | xargs)
		rm $job.res.xml
		[ -z "$taskIdList" ] && echo "{Warn} get task id nil"

		for task in $taskIdList; do
			if [[ $USE_INFO == 'true' ]]; then
				url=`bkr job-logs T:$task | grep $KCOV_COMBINED_NAME`
			else
				rm -rf ${tgz_prefix}*.tgz
				url=`bkr job-logs T:$task | grep "${tgz_prefix}.*\.tgz"`
				# try again for old format
				[ -z "$url" ] && {
					tgz_prefix=kcov_all
					url=`bkr job-logs T:$task | grep "${tgz_prefix}.*\.tgz"`
				}
			fi
			[ -z "$url" ] && {
				echo "{Warn} get url nil for T:$task"
				continue
			}
			wget --no-check-certificate $url >wget-$task.log 2>&1 || {
				echo "{Warn} wget --no-check-certificate $url error, see wget-$task.log"
				rhts-submit-log -l wget-$task.log
			}
			if [[ $USE_INFO == 'true' ]]; then
				mv $KCOV_COMBINED_NAME $INFO_DIR/kcov.$job.$task.info
				echo "{Info} $job 's info file: kcov.$job.$task.info"
			else
				pkg=$(ls ${tgz_prefix}*.tgz)
				mv $pkg $TGZDIR_NAME/.
				[ "$tgz_prefix" = kcov_all ] && mv $TGZDIR_NAME/$pkg $TGZDIR_NAME/${pkg/.tgz/-$job.$task.tgz}
				echo "{Info} ${job} 's tgz file"
				ls $TGZDIR_NAME/*${job}*.tgz
			fi
		done

	done
}

merge_kcov() {
	local tgzdir=${1:-$TGZDIR_NAME}
	local kcovcomb_file=${2:-kcovcomb.info}  #output file name

	if [[ $USE_INFO != 'true' ]]; then
		[ -d "$tgzdir" ] || {
			echo "{Err} dir $tgzdir not exist."
			return 1
		}

		# get tgz file list, and extract ...
		tgzList=$(find $tgzdir -name *.tgz)
		for tgz in $tgzList; do
			tar zxf - -C $INFO_DIR "kcov.*/kcov.*.info" <"$tgz"
			mv $INFO_DIR/kcov.* $INFO_DIR/$(basename ${tgz%.tgz})
		done
	fi

	# merge all kcov.*.info file
	fileList=$(find $INFO_DIR -name 'kcov.*.info')
	for f in $fileList; do
		optList="$optList --add-tracefile $f"
	done
	lcov --output-file "$kcovcomb_file" $optList
}

kcov_genhtml() {
	local info_file=${1:-kcovcomb.info}
	local test_list=${KCOV_TEST_LIST}
	local desc_file=${KCOV_DESC}

	if [ "$GENCASELIST" == "YES" ]; then
		awk '/^[^\t]/{printf("%06d_",int(i++))} {print}' $test_list > ${test_list}.new
		gendesc -o $desc_file ${test_list}.new
		descOption="--description-file $desc_file"
	fi

	genhtml --show-details --title "Coverage of kernel tests" --keep-descriptions --legend --highlight -o kcov.comb $info_file $descOption
	srcfile1=$(sed -n '/^SF:/{p; q}' $info_file | sed 's/^SF://')
	test -e ${srcfile1} || {
		echo "{Warn} source file [$srcfile1] not exist."
		echo "{Warn} you can download src.rpm from $REPO, and run genthml again."
	}
}

[ -z "$GENCASELIST" ] && GENCASELIST=YES
KCOV_TEST_LIST=test.list
KCOV_DESC=test.desc
JOBS=${JOBS:-"$@"}
JOBS=${JOBS:-"J:$JOBID"}

# work space dir for every merge
RESDIR=kcov_merged.`date +%F`
#dirname created by download_kcov, used to save the kcov_all*.tgz files created by kcov/finalize
TGZDIR_NAME=kcov_tgz
INFO_DIR=kcov_info_dir

# __main__
install_lcov

[ -n "$JOBID" ] && {
	# install src used by genhtml
	if [ -n "$KCOV_SRC_RPM" ]; then
		rpm -ivh $KCOV_SRC_RPM
	else
		XY=${XY:-$(lsb_release -sr)}
		kver=${RHEL_KRNL[${XY//./}]}
		rpm -ivh $REPO/$kver.gcov/$(arch)/kernel-gcov-$kver.gcov.$(arch).rpm
	fi
}

mkdir -p $RESDIR
pushd $RESDIR
	if ! download_kcov $JOBS ; then
		report_result "$TEST/download_kcov" "FAIL"
		exit
	fi
	if ! merge_kcov ./$TGZDIR_NAME kcovcomb.info ; then
		report_result "$TEST/merge_kcov" "FAIL"
		exit
	fi
	kcov_genhtml kcovcomb.info
	rc=$?
popd

if [ -z "$JOBID" ]; then
	tar -czf ${RESDIR//:/-}.tgz $RESDIR
else
	tar -czf ${RESDIR//:/-}.tgz $RESDIR/kcovcomb.info $RESDIR/kcov.comb
	rhts-submit-log -l ${RESDIR}.tgz
	if [ "$rc" = 0 ]; then
		report_result "$TEST" "PASS"
	else
		report_result "$TEST" "FAIL"
	fi
fi

exit $rc
