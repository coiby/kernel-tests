#!/bin/bash
#
# Copyright (c) 2020-2021 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)

function get_user_home_dir
{
    cki_debug

    typeset user=${1:-"$(id -un)"}
    typeset home_dir=$(egrep "^$user:" /etc/passwd | \
               awk -F':' '{print $6}')
    [[ -z $home_dir ]] && return 1
    echo $home_dir
    return 0
}

function get_test_root
{
    typeset home_dir=$(get_user_home_dir $(id -un))
    echo "$home_dir/.dmtest"
}

function get_test_log_dir
{
    typeset test_root=${1:-$(get_test_root)}
    echo "$test_root/log"
}

function get_test_reports_dir
{
    typeset test_root=${1:-$(get_test_root)}
    echo "$test_root/reports"
}

DT_TARBALL="https://github.com/RobinTMiller/dt/archive/master.zip"
function install_dt
{
    cki_debug

    typeset tarball=$(basename $DT_TARBALL)
    wget -O /tmp/$tarball $DT_TARBALL || return 1
    pushd /tmp
    unzip $tarball
    pushd dt-master/linux-rhel7x64
    make -f ../Makefile.linux VPATH=.. OS=linux || return 1
    install -m 755 -d /usr/local/bin || return 1
    install -m 755 dt /usr/local/bin || return 1
    popd
    popd
    return 0
}

BLKTRACE_TARBALL="https://git.kernel.dk/cgit/blktrace/snapshot/blktrace-1.2.0.tar.gz"
function install_blktrace
{
    cki_debug
    typeset tarball=$(basename $BLKTRACE_TARBALL)
    wget -O /tmp/$tarball $BLKTRACE_TARBALL || return 1
    pushd /tmp
    tar zxf $tarball
    pushd /tmp/${tarball%.tar.gz}
    make || return 1
    make install || return 1
    popd
    popd
    return 0
}

function install_ruby
{
    cki_debug


    curl -L https://get.rvm.io | bash || return 1
    usermod -a -G rvm $(id -un) || return 1
    umask u=rwx,g=rwx,o=rx || return 1

    source /etc/profile.d/rvm.sh || return 1

    if ! rvm install 2.5.3; then
        # Try to upload the installation logs
        rvm_logs=$(ls /usr/local/rvm/log/*/*.log)
        for log in $rvm_logs; do
            cki_upload_log_file $log
        done
        return 1
    fi
    gem update || return 1
    gem install bundler || return 1
    return 0
}

function check_mntpoint_quota
{
    cki_debug
    typeset mntpoint=${1:-"/"}
    typeset quota=${2:-"22000M"}
    typeset avail=$(df -H | egrep "$mntpoint$" | \
            awk '{print $(NF-2)}')
    typeset n=$(echo $avail | sed 's/M\|G\|T//g')
    #
    # XXX: To make things simple, we just support to check 'M|G|T' only.
    #      That is, if the available disk quota of a moint point is more
    #      than 1T, also return false
    #
    [[ $avail != *"M" && $avail != *"G" && $avail != *"T" ]] && return 1
    [[ $avail == *"G" ]] && n=$(echo "$n * 1024" | bc)
    [[ $avail == *"T" ]] && n=$(echo "$n * 1024 * 1024" | bc)
    # rstrip ".*" if n is a float as (( n )) doesn't support float
    n=${n%.*}

    quota=$(echo $quota | sed 's/M\|G\|T//g')
    (( n > quota )) && return 0 || return 1
}

function ts_config_setup
{
    #
    # XXX: Get metadata_dev and data_dev on SUT(system under test)
    #
    # It assumes the system is provisioned with 2 partitions,
    # one partition for the metadata and another for the data.
    #
    # A metadata dev of 1G, and data dev of 4G is sufficient.
    # Some poorly written tests use all of the data dev, no matter how big
    # it is, so will take longer to run with large volumes.
    #
    cki_debug

    typeset f_conf=${1?"*** config file ***"}

    mnt_metadata=/mnt/dmtest/metadata
    mnt_data=/mnt/dmtest/data

    if ! df | grep ${mnt_metadata} ; then
        echo "FAIL: Couldn't find metadata device"
        return 1
    fi
    if ! df | grep ${mnt_data} ; then
        echo "FAIL: Couldn't find data device"
        return 1
    fi

    metadata_device=$(df ${mnt_metadata} | tail -n 1 | awk '{print$1}')
    data_device=$(df ${mnt_data} | tail -n 1 | awk '{print$1}')

    if ! umount ${mnt_metadata} ${mnt_data} ; then
        echo "FAIL: umount ${mnt_metadata} ${mnt_data}"
        return 1
    fi
    if ! lsblk ; then
        echo "FAIL: lsblk"
        return 1
    fi

    echo "INFO: Metadata device: ${metadata_device}"
    echo "INFO: Data device ${data_device}"

    cat > $f_conf << EOF
profile :cki do
  metadata_dev '${metadata_device}'
  data_dev '${data_device}'
end

default_profile :cki
EOF

    echo "INFO: show $f_conf"
    cat $f_conf || return 1

    return 0
}

DMTS_REPO="https://github.com/jthornber/device-mapper-test-suite.git"
DMTS_LOCAL="/opt/$(basename $DMTS_REPO | sed 's%.git%%')"
function ts_setup
{
    cki_debug

    if ! rpm -q blktrace; then
        install_blktrace || return $CKI_UNINITIATED
    fi
    if ! rpm -q dt; then
        install_dt || return $CKI_UNINITIATED
    fi
    modprobe dm-thin-pool || return $CKI_UNINITIATED

    #
    # XXX: Have to support to set up the test enviroment only once because
    #      the setup phase of device mapper suite [1] is not very robust
    #      due to ruby setup
    #      [1] https://github.com/jthornber/device-mapper-test-suite.git
    #
    typeset f_done=$CDIR/.ts_setup
    [[ -f $f_done && $(cat $f_done) == "DONE" ]] && return $CKI_PASS

    install_ruby || return $CKI_UNINITIATED
    rm -rf $DMTS_LOCAL
    git clone $DMTS_REPO $DMTS_LOCAL || return $CKI_UNINITIATED
    pushd $DMTS_LOCAL
    bundle update || return $CKI_UNINITIATED
    popd

    typeset test_root=$(get_test_root)
    typeset subdirs="$test_root"
    subdirs+=" $(get_test_log_dir $test_root)"
    subdirs+=" $(get_test_reports_dir $test_root)"
    for subdir in $subdirs; do
        if [[ ! -d $subdir ]]; then
            mkdir -p -m 0755 $subdir || return $CKI_UNINITIATED
        fi
    done

    ts_config_setup $test_root/config || return $CKI_UNINITIATED
    echo "DONE" > $f_done

    return $CKI_PASS
}
