#!/bin/bash

release="$(uname -r)"
machine="$(uname -m)"

# EPEL7 only builds sysbench for x86_64
if [[ "$release" =~ el7 && "$machine" =~ x86_64 ]]; then
	subscription-manager repos --enable rhel-*-optional-rpms \
				--enable rhel-*-extras-rpms \
				--enable rhel-ha-for-rhel-*-server-rpms
	yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
	yum -y install sysbench
# But EPEL8 builds sysbench packages for all architectures
elif [[ "$release" =~ el8 ]]; then
	subscription-manager repos --enable "codeready-builder-for-rhel-8-$(arch)-rpms"
	dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
	dnf -y install sysbench
# While EPEL9 only builds sysbench for x86_64 and aarch64
elif [[ "$release" =~ el9 && "$machine" =~ (x86_64)|(aarch64) ]]; then
	subscription-manager repos --enable "codeready-builder-for-rhel-9-$(arch)-rpms"
	dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
	dnf -y install sysbench
else
	echo "The sysbench package is not available for $(cat /etc/redhat-release) on $machine."
	exit 1
fi
