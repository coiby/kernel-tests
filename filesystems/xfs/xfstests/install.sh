#! /bin/bash -x
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   This file includes functions that install some utilities
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

. ../../../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

if type -P yum >/dev/null; then
	YUM_PROG=$(type -P yum)
	YUM_OPTS="-y --skip-broken"
fi
if [[ -e /run/ostree-booted ]];then
	YUM_PROG="$(type -P rpm-ostree)"
	YUM_OPTS="--apply-live --idempotent --allow-inactive "
fi
if type -P dnf >/dev/null && ! [[ -e /run/ostree-booted ]]; then
	YUM_PROG="$(type -P dnf)"
	YUM_OPTS="-y --best --allowerasing --setopt=strict=0"
fi
if type -P dnf5 >/dev/null && ! [[ -e /run/ostree-booted ]]; then
	YUM_PROG="$(type -P dnf5)"
	YUM_OPTS="-y --best --setopt=strict=0"
fi

# Install xfsprogs from upstream (or any other) repo
# Needs XFSPROGS_GITBRANCH and XFSPROGS_GITREPO
function install_xfsprogs_git_upstream ()
{
	local repo=$(echo "$XFSPROGS_GITREPO" | sed -e "s_.*/\([^/]*\)\$_\1_g" -e "s/\.git\$//")
	if [ "$XFSPROGS_GITBRANCH" != "" ]
	then
		git clone --branch "$XFSPROGS_GITBRANCH" "$XFSPROGS_GITREPO"
	else
		git clone  "$XFSPROGS_GITREPO"
	fi
	cd "$repo"
	make
	make install
	make install-dev
	local res=$?

	local libhandleLoop=$(ls -l /lib64/libhandle.so| awk '{if ($9 == $11) { print "loop"}}')
	if [ "$libhandleLoop" == "loop" ]; then
		rm /lib64/libhandle.so
		ln -s /lib64/libhandle.so.1 /lib64/libhandle.so
	fi

	cd ..
	return $res
}

# Install xfsprogs and xfsprogs-devel if they are not already installed in the system
# optionally can have XFSPROGS_GITREPO to install from a git repository
function install_xfsprogs()
{
	local rc=0

	if test "$XFSPROGS_GITREPO"; then
		xlog install_xfsprogs_git_upstream
		rc=$?
	else
		if ! rpm -q xfsprogs xfsprogs-devel >/dev/null 2>&1;then
			$YUM_PROG $YUM_OPTS install xfsprogs xfsprogs-devel
		fi

		rpm -q xfsprogs xfsprogs-devel >/dev/null 2>&1
		rc=$?
	fi

	if [ $rc -eq 0 ];then
		report install_xfsprogs PASS 0
		return 0
	else
		report install_xfsprogs FAIL 0
		return 1
	fi
}

# Install xfsdump if it is not already installed
function install_xfsdump()
{
	XFSDUMP="xfsdump"
	rpm -q --quiet "${XFSDUMP}"

	$YUM_PROG $YUM_OPTS install xfsdump
	# To propagate exit code
	if rpm -q "${XFSDUMP}";then
		report install_xfsdump PASS 0
		return 0
	else
		report install_xfsdump FAIL 0
		return 1
	fi
}

# Install dbench if it is not already installed
function install_dbench()
{
	if dbench --help > /dev/null 2>&1; then
		return 0
	else
		git clone git://git.samba.org/sahlberg/dbench.git dbench
		cd dbench
		patch -p1 < ../0001-dbench-fix-build-error-on-RHEL8.patch
		./autogen.sh
		./configure > /dev/null 2>&1
		make > ../dbench.build 2>&1
		make install > /dev/null 2>&1
		cd ..
	fi
	if dbench --help > /dev/null 2>&1 ; then
		report install_dbench PASS 0
		return 0
	else
		report install_dbench FAIL 0
		cat dbench.build
		return 1
	fi
}

# Install fio from upstream
function install_fio_git_upstream()
{
	local repo="git://git.kernel.dk/fio.git"

	git clone $repo | tee build-fio-upstream.log
	if [ $? -eq 0 ]; then
		pushd fio
		local last_tag=$(git describe --tags `git rev-list --tags --max-count=1`)
		# fio-3.20 breaks build on RHEL7
		[[ `uname -r` =~ el7 ]] && last_tag=fio-3.19
		echoo "Choose fio $last_tag"
		git checkout -b $last_tag $last_tag
		make >> ../build-fio-upstream.log 2>&1
		make install >> ../build-fio-upstream.log 2>&1
		popd
	fi
}

# Install fio if it is not already installed
function install_fio()
{
	FIO="fio"

	$YUM_PROG $YUM_OPTS install $FIO
	rpm -q --quiet "${FIO}"

	fio -v
	if [ $? -ne 0 ]; then
		install_fio_git_upstream
	fi

	fio -v
	if [ $? -eq 0 ]; then
		report install_fio_git_upstream PASS 0
		return 0
	else
		rstrnt-report-log -l build-fio-upstream.log
		report install_fio_git_upstream FAIL 0
		return 1
	fi
}

install_duperemove()
{
	local res=0

	# Just return if duperemove has been installed
	if type -P duperemove; then
		return 0
	fi

	# Try to install the package directly
	$YUM_PROG $YUM_OPTS install duperemove
	if rpm -q duperemove; then
		return 0
	fi

	# Clone the source code
	git clone https://github.com/markfasheh/duperemove.git
	if [ $? -ne 0 ]; then
		return 1
	fi

	# Install necessary build dependences
	$YUM_PROG $YUM_OPTS install glib2 glib2-devel libatomic sqlite sqlite-devel

	# Build
	pushd duperemove
	make && make install
	duperemove --help >/dev/null 2>&1
	res=$?
	popd

	return $res
}

# Full install of xfs and xfstests related packages
function install_xfs()
{
	install_xfsprogs
	install_xfsdump
	#install_dbench
	install_fio
	install_duperemove
}


# Install xfstests from upstream (or any other) repo
# Needs GITBRANCH and GITREPO
function install_xfstests_git_upstream ()
{
	local res=0
	local repo=$(echo "$GITREPO" | sed -e "s_.*/\([^/]*\)\$_\1_g" -e "s/\.git\$//")
	echo $repo $GITREPO $GITBRANCH
	rm -rf xfstests xfstests-dev
	if [ "$GITBRANCH" != "" ];then
		git clone --depth 1 --branch "$GITBRANCH" "$GITREPO" ||
		git clone --depth 1 --branch "$GITBRANCH" "$GITREPO_PLANB"
	else
		git clone --depth 1 "$GITREPO" ||
		git clone --depth 1 "$GITREPO_PLANB"
	fi
	[ -d $repo ] || return 1

	cd "$repo"
	grep _filter_stat common/filter || patch -p1 < ../f33-stat.patch
	grep std=gnu include/builddefs.in || patch -p1 < ../gcc15-workaround.patch
	make
	rm -f configure
	rm -fr tests/ceph/
	make && make install
	res=$?
	cd ..
	return $res
}

# Install xfstests from our internal git repo
# Needs GITBRANCH, SERVER
# Sets HARNESS* variables
function install_xfstests_git()
{
	HARNESS="xfstests"
	HARNESS_VER="99999999-3.git"
	HARNESS_BAS="$HARNESS-$HARNESS_VER"
	HARNESS_SRPM="$HARNESS_BAS.src.rpm"
	rm -rf xfstests-dev
	git clone --branch "$GITBRANCH" git://git.kernel.org/pub/scm/fs/xfs/xfstests-dev.git xfstests-dev
	cd xfstests-dev
	git archive --format=tar --output /root/xfstests-dev.tar --prefix=xfstests-dev/ $GITBRANCH
	cd ../
	bzip2 -f /root/xfstests-dev.tar
	wget -N "$SERVER/${HARNESS_SRPM}"
	rpm -ivh "${HARNESS_SRPM}" || return 1
	cd ~/rpmbuild/SPECS/ || cd /usr/src/redhat/SPECS || return 2
	cp -f /root/xfstests-dev.tar.bz2 ../SOURCES/xfstests-dev.tar.bz2
	rpmbuild -bb xfstests.spec 2>&1 | tee build.log
	RPM=`grep -E "Wrote.*$HARNESS_BAS" build.log | awk '{print $NF}'`
	rpm -e xfstests
	yum install --nogpgcheck -y $RPM
	cd -
	rpm -q $HARNESS
	return $?
}

# Install xfstests from pkg residing in one of our internal servers
# Needs GITDATE, SERVER
# Sets HARNESS* variables
function install_xfstests_pkg()
{
	HARNESS="xfstests"
	HARNESSREL="${GITDATE}.git"
	HARNESS_SRPM="${HARNESS}-${HARNESSREL}.src.rpm"
	rpm -q --quiet ${HARNESS}-${HARNESSREL}

	if test $? -ne 0
	then
		# First, uninstall xfstests to allow a potential downgrade
		rpm -e xfstests
		# install xfstests
		wget -N "${SERVER}/${HARNESS_SRPM}"

		rpmbuild --rebuild ${HARNESS_SRPM} 2>&1 | tee  build.log

		RPM=`grep -E "Wrote.*${HARNESS}-[0-9]" build.log | awk '{print $NF}'`

		# use yum here to resolve dependcies automatically in rhts
		yum install --nogpgcheck -y $RPM
	fi
	rpm -q $HARNESS-$HARNESSREL

	return $?
}

# Wrapper to pkg and git install of xfstets
# Needs GITDATE or GITBRANCH, optionally also GITREPO
function install_xfstests()
{
	if [[ "x$GITBRANCH" == "x" ]] && [[ "x$GITREPO" == "x" ]] ; then
		# GITBRANCH is not set, maybe the user used GITDATE
		case "$GITDATE" in
		master|stable|testing)
			# set GITBRANCH to GITDATE to keep GITDATE's old behavior
			export GITBRANCH=$GITDATE
			;;
		keep)
			# User wished to keep the installed version of xfstests
			;;
		*)
			xlog install_xfstests_pkg
			if test $? -ne 0;then
				report install_xfstests FAIL 0
				exit 1
			fi
			;;
		esac
	fi

	if [[ "$GITBRANCH" != "" ]] || [[ "$GITREPO" != "" ]]; then
		# GITBRANCH could be set within the previous code block,
		# so this can't be an "else" branch, but full "if".
		if [ "$GITREPO" != "" ];then
			xlog echo "Using given git repository."
			xlog install_xfstests_git_upstream
		else
			xlog echo "Using built-in git repo."
			xlog install_xfstests_git
		fi
		if test $? -ne 0;then
			report install_xfstests FAIL 0
			exit 1
		fi
	fi

	report install_xfstests PASS 0
	return 0
}

# make sure proper kernel-debuginfo be installed
function install_kernel_debuginfo()
{
	local KERNELARCH=`uname -m`
	local KERNELNAME=$(rpm -q --queryformat '%{name}' -qf /boot/config-`uname -r`)
	local KERNELVERSION=$(rpm -q --queryformat '%{version}-%{release}' -qf /boot/config-`uname -r`)
	local DEPPKGS="${KERNELNAME}-devel-${KERNELVERSION}.${KERNELARCH} ${KERNELNAME}-debuginfo-${KERNELVERSION}.${KERNELARCH} kernel-debuginfo-common-${KERNELARCH}-${KERNELVERSION}.${KERNELARCH}"
	rpm -q ${DEPPKGS}
	if [ $? -ne 0 ];then
		downloadBrewBuild kernel-${KERNELVERSION} --arch=${KERNELARCH} --debuginfo
		xlog rpm -ivh --force ${KERNELNAME}-devel*.rpm ${KERNELNAME}-debuginfo*.rpm kernel-debuginfo-common*.rpm
		# use yum to make sure all dependence have been installed
		# yum reinstall --nogpgcheck -y ${KERNELNAME}-devel*.rpm ${KERNELNAME}-debuginfo*.rpm kernel-debuginfo-common*.rpm

		rpm -q ${DEPPKGS}
		if [ $? -ne 0 ];then
			echoo "Can't install $DEPPKGS !!"
			return 1
		fi
	fi
	rm -f *.rpm
	return 0
}
