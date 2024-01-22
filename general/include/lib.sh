#!/bin/sh
#shellcheck disable=SC2034

# Define of the general test ENV in kernel-general test.
KG_SERVER=vmcore.usersys.redhat.com
KG_SERVER_ALIAS=vmcore.usersys.redhat.com
KG_SERVER_USER="test"

# The http url for tools/configs. For http, the path
# /data/ is uased as root, different from nfs path.
KG_HTTP_SHARE=$KG_SERVER/share
KG_HTTP_CODECOVERAGE_KERNELS=$KG_HTTP_SHARE/gcov-kernels

# Default nfs mount point
NFS_LOCAL_MNT=/home/kg
KG_SHARE_SHARE=/data/share

# KABI related stuff
KG_SHARE_UAPI=/data/uapi_sysctl
KG_SHARE_UAPI_TEMP=/data/uapi_sysctl/temp
KG_SHARE_KABI=/data/kabi

KG_NFS_PATH_UAPI_SYSFS=$KG_SERVER:$KG_SHARE_UAPI
KG_NFS_PATH_UAPI_SYSFS_TEMP=$KG_SERVER:$KG_SHARE_UAPI_TEMP
KG_NFS_PATH_KABI=$KG_SERVER:$KG_SHARE_KABI

# Code coverage data
KG_SHARE_CODECOVERAGE_RAW=/data/kgqe/code-coverage
KG_SHARE_CODECOVERAGE_PUBLIC=/data/kgqe/CodeCoverage
KG_SHARE_CODECOVERAGE_KERNELS=/data/share/gcov-kernels

# https://sourceforge.net/projects/ltp/files/Coverage Analysis/
# 20220401

# extra gcov kernel packages for use, could be a repo folder, or not
# for test cases using srpm to reference
KG_GCOV_RPMS=/mnt/gcov_rpms/
KG_LCOV_PACAGE=lcov-1.15-1.noarch.rpm
KG_HTTP_CODECOVERAGE_TOOL=$KG_HTTP_SHARE/$KG_LCOV_PACAGE

KG_NFS_PATH_CODE_COVERAGE_RAW=$KG_SERVER:$KG_SHARE_CODECOVERAGE_RAW
KG_NFS_PATH_CODE_COVERAGE_PUBLIC=$KG_SERVER:$KG_SHARE_CODECOVERAGE_PUBLIC

read -r sourcerpm <<< $(rpm -q --queryformat '%{SOURCERPM}' -f "/boot/config-$(uname -r)")
kernel_spec=$(echo "${sourcerpm%%-[0-9]*}")
running_kernel=$(echo $sourcerpm | sed 's/\.src.rpm//' | sed 's/^[^0-9]*//')

# DUP ISO images
KG_SHARE_DUP_ISO=/data/dup
KG_NFS_PATH_DUP=$KG_SERVER:$KG_SHARE_DUP_ISO

rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')
rhel_minor=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $2}')

function download_kernel_srpm()
{
	# Since 9.3 PREEMPT_RT patch merge and build kernel-rt as a variant,
	# kernel-rt will use the kernel source package to build.
	HOST=$(hostname)
	case ${HOST} in
		*pek*) def_url="http://download.eng.pek2.redhat.com/brewroot/packages";;
		*rdu*) def_url="http://download.eng.rdu.redhat.com/brewroot/packages";;
		*bos*) def_url="http://download.eng.rdu2.redhat.com/brewroot/packages";;
		*brq*) def_url="http://download.eng.brq.redhat.com/brewroot/packages";;
		*tlv*) def_url="http://download.eng.tlv.redhat.com/brewroot/packages";;
		*blr*) def_url="http://download.eng.blr.redhat.com/brewroot/packages";;
		*pnq*) def_url="http://download.eng.pnq.redhat.com/brewroot/packages";;
		*) def_url="http://download.devel.redhat.com/brewroot/packages";;
	esac

	package_prefix="$def_url/$kernel_spec"
	kernel_maj=$(uname -r | cut -d- -f1)
	tmp=$(uname -r | cut -d- -f2)
	kernel_min=$(echo ${tmp%.*})

	ksrpm_url=$package_prefix/$kernel_maj/$kernel_min/src/$sourcerpm
	wget -q $ksrpm_url
	sleep 10
}

function setup_src_repo()
{
	local baseurl=$(grep baseurl /etc/yum.repos.d/beaker-BaseOS.repo | awk -F'BaseOS' -vOFS='' '{$1=$1;$2=""}1')

	if [[ $kernel_spec =~ "rt" ]]; then
		local varient="RT"
	else
		local varient="BaseOS"
	fi

cat << EOF > /etc/yum.repos.d/${repo_name:-"beaker-source.repo"}
[beaker-source]
name=beaker-source
${baseurl}${varient}/source/tree/
enabled=1
gpgcheck=0
skip_if_unavailable=1
EOF
}

function cleanup_src_repo()
{
	rm -fr /etc/yum.repos.d/${repo_name:-"beaker-source.repo"}
}

function prepare_running_kernel_src()
{
	echo $running_kernel | grep -q -v 'el[0-9]\|fc\|eln'
	if [ $? -eq 0 ]; then
		echo "detected upstream kernel..."
		echo "copy /usr/src/kernels/${running_kernel} to linux-${running_kernel}"
		cp -r /usr/src/kernels/${running_kernel} linux-${running_kernel}
	else
		echo "download src package from RH site"
		setup_src_repo
		# dnf download parameter should not include ".src.rpm"
		local download_srpm=$(echo $sourcerpm | sed 's/\.src\.rpm//')
		dnf download --source $download_srpm || download_kernel_srpm
		cleanup_src_repo
		if ! test -f $sourcerpm; then
			echo "RPM package download failed"
			rstrnt-report-result "srpm-download" "FAIL" 1
			exit 1
		fi
		rpm -ivh --force $sourcerpm
		tar xf /root/rpmbuild/SOURCES/linux-*.tar.xz -C .
	fi
}

# Helper functions for mount/umount nfs.
# The default server is $KG_SERVER, can override it by
# defining the USER_NFS_SERVER=servername
function mount_nfs()
{
	local server_name=${USE_NFS_SERVER:-$KG_SERVER}
	local server_share=$1
	local mount_point=${2:-$NFS_LOCAL_MNT}
	[ ! -d $NFS_LOCAL_MNT ] && mkdir $NFS_LOCAL_MNT
	rlRun "mount -t nfs $server_name:$server_share $mount_point" 0-254
	mount | grep $server_name:$server_share
	[ $? -ne 0 ] && rlDie "There is no server mount.Cant get the data,abort now."
}

function umount_nfs()
{
	umount ${1:-$NFS_LOCAL_MNT}
}

###================== Repo setup =========================
function setup_yum_repo()
{
	local name=${1:-kernel}
	local vr=${2}
	local baseurl=${3:-}
	if [ -z "$vr" ]; then
		if uname -r | grep -E "el[0-9]"; then
			echo "Repo for RHEL kernel $(uname -r)"
			vr=$(uname -r | grep -Eo ".*el[0-9]+")
			local version=$(echo $vr | cut -d- -f1)
			local release=$(echo $vr | cut -d- -f2)
		fi
	else
		echo "Can't config this repo. This is upstream pkg!"
		return 1
	fi

cat > /etc/yum.repos.d/testrepo_${name}.repo <<EOF
[testrepo-${name}]
name=Server-optional
baseurl=${baseurl}/${name}/${version}/${release}
enabled=1
gpgcheck=0
skip_if_unavailable=1
EOF
}

###================ Stress-ng install ==========================

# For installing stressor stress-ng, copied from kpatch/cmdline
function stress_ng_install()
{
	local input_commit=$1

	local REL_ID=$(awk -F= '/^ID=/ {gsub("\"","",$2);print $2}' /etc/os-release)
	local major=$(awk -F= '/^VERSION_ID=/ {gsub("\"","",$2);split($2,a,".");print a[1]}' /etc/os-release)
	local minor=$(awk -F= '/^VERSION_ID=/ {gsub("\"","",$2);split($2,a,".");print a[1]}' /etc/os-release)

	local patch_cmd="git am "
	local commit=${input_commit:-"81d8c27"}
	local dirname=stress-ng
	local ret=0

	# The v0.12.05 version don't show process command to stress-ng-{stressor} with ps
	# but with stress-ng only, so can't distinguish with process names. Have to use old
	# version.
	if [ "$major" -ge 9 ] || [ "$REL_ID" = fedora ]; then
		echo "Use in-tree stress-ng rpm in rhel-9.0+"
		which stress-ng &>/dev/null && echo "stress-ng allready installed" || yum -y install stress-ng
		which stress-ng
		return $?
	elif [ "$major" -ge 8 ] && [ "$REL_ID" = rhel ] || [ "$REL_ID" = fedora ]; then
		commit=${input_commit:-"81d8c27"}
		echo Using commit $commit V0.09.47
	fi
	test -f ERROR && rm -f ERROR
	test -d $dirname && rm -fr $dirname

	if ((1)) || [ ! -f /usr/bin/stress-ng ]; then
		echo "Fetching stress-ng and installing dependencies pkgs"
		yum install -y libattr-devel keyutils-libs-devel libcap-devel \
		libaio-devel lksctp-tools-devel libseccomp-devel zlib-devel \
		libsemanage-devel libatomic_ops-devel liblockfile-devel numactl-devel \
		libseccomp-devel --nogpgcheck &>/dev/null
		yum install -y git --nogpgcheck &>/dev/null
		yum groupinstall -y development --nogpgcheck &>/dev/null

		if ((1)); then
			#  commit id: 0389f3308460 (Tag: V0.12.05 +1) (Date: 20210317)
			LOOKASIDE=${LOOKASIDE:-http://download.devel.redhat.com/qa/rhts/lookaside}
			local pkgname=stress-ng.${commit}.tar.gz
			echo "Trying to get stress-ng from lookaside $LOOKASIDE/$pkgname"
			curl -LkO $LOOKASIDE/$pkgname
			if ! test -f $pkgname; then
				ecoh "Failed to get Lookaside from $LOOKASIDE/$pkgname "
				return 1
			fi
			test -d $dirname && rm -fr $dirname
			tar -zxf $pkgname
			dirname=stress-ng.${commit}
			patch_cmd="patch < "
		fi

		test -d $dirname
		ret=$?
		if [ "$ret" -ne 0 ]; then
			dirname=stress-ng
			echo "Tring to get stress-ng from github: https://github.com/ColinIanKing/stress-ng.git"
			git clone https://github.com/ColinIanKing/stress-ng.git
			test -d $dirname
			ret=$?

			if [ $ret = 0 ]; then
				pushd stress-ng
				git checkout $commit -b $commit
				popd
			fi
		fi

		if [ "$commit" = 81d8c27 ]; then
			pushd $dirname

			eval $patch_cmd ../../../include/patches/stress-ng/0001-stress-ng-support-sched-deadline.patch || \
			{ echo "==== patch 0001 stress-ng failed !"; exit 1; }
			eval $patch_cmd ../../../include/patches/stress-ng/0002-stress-ng-child-reset-deadline-scheduler.patch || \
			{ echo "==== patch 0002 stress-ng failed !"; exit 1; }
			eval $patch_cmd ../../../include/patches/stress-ng/0003-stress-ng-sched-support-grub-protocol-for-deadline-s.patch || \
			{ echo "==== patch 0003 stress-ng failed !"; exit 1; }
			eval $patch_cmd ../../../include/patches/stress-ng/0004-stress-ng-deadline-default-bandwidth-0.05.patch || \
			{ echo "==== patch 0004 stress-ng failed !"; exit 1; }
			eval $patch_cmd ../../../include/patches/stress-ng/0005-stress-ng-Fix-pragma-version-check.patch || \
			{ echo "==== patch 0005 stress-ng failed !"; exit 1; }
			eval $patch_cmd ../../../include/patches/stress-ng/0006-stress-ng-Fix-weird-syntax.patch || \
			{ echo "==== patch 0006 stress-ng failed !"; exit 1; }
			eval $patch_cmd ../../../include/patches/stress-ng/0007-stress-ng-Fix-stress-ng-on-undeadline.patch || \
			{ echo "==== patch 0007 stress-ng failed !"; exit 1; }
			eval $patch_cmd ../../../include/patches/stress-ng/0008-stress-ng-Fix-undefined-sched_deadline_init.patch || \
			{ echo "==== patch 0008 stress-ng failed !"; exit 1; }

			popd
		fi

		echo "Building stress-ng"
		ret=0
		make -C $dirname clean
		make -C $dirname || ret+=1
		echo "Installing stress-ng"
		make -C $dirname install || ret+=1

		if ((ret == 0)); then
			echo "Install stress-ng finished"
		else
			echo "Install stress-ng failed"
		fi
	else
		echo "stress-ng has already been installed"
		echo "$(which stress-ng)"
	fi
	return $ret
}

# ================ sysbench install ============================

function bench_sysbench_install()
{
	wget http://download.devel.redhat.com/brewroot/packages/sysbench/0.4.12/13.el7ostarch/src/sysbench-0.4.12-13.el7ostarch.src.rpm
	rpmbuild -bp sysbench-0.4.12-13.el7ostarch.src.rpm
	yum-builddep -y  sysbench-0.4.12-13.el7ostarch.src.rpm
	rpmbuild -bb ./sysbench-0.4.12-13.el7ostarch.src.rpm
	rpmbuild --rebuild -bb  ./sysbench-0.4.12-13.el7ostarch.src.rpm
	rpm -ivh /root/rpmbuild/RPMS/$(uname -m)/sysbench-0.4.12-13.el7.$(uname -m).rpm
	which sysbench
}
