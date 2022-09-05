#!/bin/bash

# Source the common test script helpers
#. /usr/bin/rhts_environment.sh

function is_validurl()
{
    local url=$1
    curl --fail --location $url > /dev/null 2>&1
    return $?
}


function config_repo()
{
    local url="$1/`uname -m`/"

echo "- enable candidate repo $url"
cat << EOF >/etc/yum.repos.d/beaker-Server-candidate.repo
[beaker-Server-candidate]
name=beaker-Server
baseurl=$url
enabled=1
gpgcheck=0
EOF

    yum clean all
    yum makecache

    if [ -z "$UPDATE" ]; then
        exit 0;
    fi

    if [ "$UPDATE" == "all" ]; then
        echo "- system update."
        yum update -y
        reboot && sleep 1
        exit 0;
    fi

    echo "- update packages $UPDATE."
    for package in $UPDATE
    do
        rpm -q $package && yum update -y $package || yum install -y $package
    done

    debugkernel=$(rpm -ql kernel-debug | grep '/boot/vmlinuz')
    if [ -n "$debugkernel" ]; then
        grubby --set-default="$debugkernel"
        zipl > /dev/null 2>&1
    fi

    echo $UPDATE | grep kernel && reboot && sleep 1

    exit 0;
}


if [ -f "/etc/yum.repos.d/beaker-Server-candidate.repo" ]; then
    echo "- packages update done, system rebooted"
    exit 0;
fi

if [ -n "$KERNARGS" ]; then
    grubby --args="$KERNARGS" --update-kernel=ALL
fi

UPDATE="${UPDATE:-}"
ZSTREAM_REPO="${ZSTREAM_REPO:-no}"

REPO_BASEURL='http://download.devel.redhat.com/rel-eng/repos'
REPO_NAME='rhel'

MAJOR=$(lsb_release -rs | grep -o '^[0-9]*')
MINOR=$(lsb_release -rs | grep -o '[0-9]$')
MINOR_NEXT=$((MINOR+1))
cat /etc/redhat-release

rpm -q kernel | grep -q "el${MAJOR}a"
if [ "$?" == 0 ]; then
    REPO_NAME+='-alt'
fi

if [ "$MAJOR" -le 6 ]; then
    #use uppser case for rhel6 and before
    REPO_NAME=${REPO_NAME^^}
fi

REPO_CANDIDATES="${REPO_NAME}-${MAJOR}-latest-candidate \
    ${REPO_NAME}-${MAJOR}.${MINOR_NEXT}-candidate \
    ${REPO_NAME}-${MAJOR}.${MINOR}-candidate"


if [ "$ZSTREAM_REPO" == "yes" ]; then
    repo="${REPO_NAME}-${MAJOR}.${MINOR}-z"
    if [ "$MAJOR" -le 6 ]; then
        repo="${REPO_BASEURL}/${repo^^}-candidate"
    fi

    is_validurl $repo && config_repo $repo
    echo "- did not find repo $repo"
    exit 0;
fi


for candidate in $REPO_CANDIDATES
do
    repo="${REPO_BASEURL}/${candidate}"
    is_validurl $repo && config_repo $repo
done

echo "- rhel ${MAJOR}.${MINOR} candidate repo did not found."
exit 0


