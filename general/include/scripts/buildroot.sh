#!/bin/bash
set -x

# For installing packages from buildroot in rhel8+

this_arch=$(uname -m)
this_distro=$(awk -F- '/DISTRO/ {gsub("[ \t]",""); print $3}' /etc/motd) # E.G. 20210224.[nd].4 or 20210224.6
pre_distro=$(echo $this_distro | awk -F. '{if (NF ==2) {print $1} else if (NF==3) {printf("%s.%s\n",$1,$2)}}')
end_distro=$(echo $this_distro | awk -F. '{print $NF}')

maj_rel=$(grep -oE "[0-9]\.[0-9]" /etc/redhat-release | cut -d. -f1)
min_rel=$(grep -oE "[0-9]\.[0-9]" /etc/redhat-release | cut -d. -f2)

info="$0: Install package from buildroot for rhel${maj_rel}."
test -z "$*" && echo -e "$info\nUsage:\n $0 <pkg> [ <pkg> ... ]"  && exit 1

if [[ "$1" =~ "repo_setup" ]]; then
	reserve_repo=1
	repo_name=$(echo $1 | awk -F'=' '{print $2}')
	shift
fi

buildroot_latest=http://download.eng.bos.redhat.com/rhel-${maj_rel}/nightly/BUILDROOT-${maj_rel}/latest-BUILDROOT-${maj_rel}.${min_rel}.0-RHEL-${maj_rel}/compose/Buildroot/$this_arch/os/

if grep -qi 'Red Hat' /etc/redhat-release && ((maj_rel > 7)); then
	repo_buildroot=$buildroot_latest
	if ! curl -s --fail --head $repo_buildroot; then
		echo "Failed to get buildroot repo, aborting ..."
		exit 1
	fi

	echo Using buildroot repo $repo_buildroot
	cat << EOF > /etc/yum.repos.d/${repo_name:-buildroot.repo}
[beaker-BUILDROOT]
name=beaker-BUILDROOT
baseurl=$repo_buildroot
enabled=1
gpgcheck=0
skip_if_unavailable=1
EOF

fi

for pkg in $*; do
	yum -y install $pkg --enablerepo=beaker-CRB > /dev/null && echo "Successfully installed $pkg" || echo "Failed to install $pkg"
done

((reserve_repo)) || rm -fr /etc/yum.repos.d/${repo_name:-buildroot.repo}

