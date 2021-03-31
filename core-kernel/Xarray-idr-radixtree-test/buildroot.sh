#!/bin/bash

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

success_buildroot=0

buildroot_rhel8=http://download.eng.bos.redhat.com/rhel-8/rel-eng/BUILDROOT-8/BUILDROOT-8.${min_rel}.0-RHEL-${maj_rel}-${pre_distro}.END_DISTRO/compose/Buildroot/$this_arch/os/
buildroot_rhel8_latest=http://download.eng.bos.redhat.com/rhel-8/rel-eng/BUILDROOT-8/latest-BUILDROOT-8.${min_rel}.0-RHEL-8/compose/Buildroot/$this_arch/os/
buildroot_rhel9=http://download.eng.bos.redhat.com/rhel-9/composes/BUILDROOT-9/BUILDROOT-9.${min_rel}.0-RHEL-${maj_rel}-${this_distro}/compose/Buildroot/$this_arch/os
buildroot_rhel9_latest=http://download.eng.bos.redhat.com/rhel-9/rel-eng/BUILDROOT-9/latest-BUILDROOT-9.${min_rel}.0-RHEL-9/compose/Buildroot/$this_arch/os/

if grep -qi 'Red Hat' /etc/redhat-release && ((maj_rel > 7)); then
	if echo $this_distro | grep -q '.n'; then
		choose=nightly
	else
		choose=rel-eng
	fi
	for ((; end_distro >= 0; end_distro--)) do
		if [ ! "$success_buildroot" = 1 ]; then
			repo_buildroot=$(eval echo \$buildroot_rhel$maj_rel | sed 's/END_DISTRO/'$end_distro'/')
			echo "Trying buildroot option: $repo_buildroot"
			if curl -s --fail --head $repo_buildroot >/dev/null; then
				success_buildroot=1
				break
			fi
		fi
	done
	if ((success_buildroot == 0)); then
		repo_buildroot=$(eval echo \$buildroot_rhel${maj_rel}_latest)
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

