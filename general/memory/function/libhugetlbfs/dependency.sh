#!/bin/bash

# For glibc-static dependence issue on rhel8
# Bug 1567712 - glibc-static needs to be multilib on RHEL 8

awk -F= '/^NAME="Red Hat Ent/ {rhel=1} /^VERSION_ID="[0-9]/ {gsub("\"","");split($2,a,".")} END{if (rhel == 1 && a[1] >= 8) exit(0);exit(1)}' /etc/os-release
retval=$?
if [ $retval -eq 0 ] && test -f /etc/yum.repos.d/beaker-CRB.repo; then
	enablerepo=" --enablerepo=beaker-CRB"
	echo Using repo $(awk -F= '/baseurl/ {print $2}' /etc/yum.repos.d/beaker-CRB.repo)
elif test -n "$REPO_LINK"; then
	repo_link=${REPO_LINK:-}
	echo Using repo $repo_link
	cat << EOF > /etc/yum.repos.d/${repo_name:-CRB.repo}
[extra_repo]
name=extra_repo
baseurl=$repo_link
enabled=1
gpgcheck=0
skip_if_unavailable=1
EOF
	cleanup_cmd="rm -fr /etc/yum.repos.d/${repo_name:-CRB.repo}"
fi

yum install -y --setopt=multilib_policy=all libgcc glibc-devel glibc-static $enablerepo
# This is required in spec file in rhel8 srpm
rpm -q execstack || yum -y install execstack $enablerepo

$cleanup_cmd
