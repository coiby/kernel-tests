#!/bin/bash
#
# Copyright (c) 2023 Red Hat, Inc. All rights reserved.
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

# shellcheck source=/dev/null
source ../../../kernel-include/runtest.sh

DT_TARBALL="https://github.com/RobinTMiller/dt/archive/master.zip"
BUFIO_REPO="https://github.com/bmarzins/bufio-test/"
LINUX_REPO="https://github.com/torvalds/linux"
BLK_ARCHIVE_REPO="https://github.com/jthornber/blk-archive"
DMTS_REPO="https://github.com/jthornber/dmtest-python.git"
DMTS_LOCAL="/opt/$(basename $DMTS_REPO | sed 's%.git%%')"

function install_kernel_devel
{
    cki_debug

    devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
    rpm -q "${devel_pkg}" || yum install -y "${devel_pkg}"
    if ! rpm -q "${devel_pkg}"; then
      return 1
    fi
    return 0
}

function install_dt
{
    cki_debug

    local tarball
    tarball=$(basename $DT_TARBALL)
    wget -O /tmp/"$tarball" $DT_TARBALL || return 1
    pushd /tmp || return 1
    unzip "$tarball"
    pushd dt-master/linux-rhel7x64 || return 1
    make -f ../Makefile.linux VPATH=.. OS=linux || return 1
    install -m 755 -d /usr/local/bin || return 1
    install -m 755 dt /usr/local/bin || return 1
    popd || return 1
    popd || return 1
    return 0
}

function install_bufio
{
    cki_debug

    local bufio_dir
    bufio_dir=$(basename $BUFIO_REPO)
    if [ -e "/tmp/$bufio_dir" ]; then
        rm -rf "/tmp/$bufio_dir"
    fi
    git clone $BUFIO_REPO /tmp/"$bufio_dir" || return 1
    pushd "/tmp/$bufio_dir" || return 1
    if [[ -e /etc/redhat-release ]]; then
      os_version=$(cut -d" " -f6 /etc/redhat-release | cut -d"." -f1)
    else
      os_version=$(cut -d" " -f4 /etc/centos-release)
    fi
    git checkout rhel-"$os_version"
    make -C /lib/modules/"$(uname -r)"/build M="$PWD"
    make -C /lib/modules/"$(uname -r)"/build M="$PWD" modules_install
    popd || return 1
    return 0
}

function clone_linux_repo
{
    cki_debug

    local repo_dir="linux"
    if [ -e "$DMTS_LOCAL"/"$repo_dir" ]; then
        echo "Linux repo already exists in $DMTS_LOCAL!"
        return 0
    fi
    if ! git clone $LINUX_REPO "$DMTS_LOCAL"/"$repo_dir"; then
      return 1
    fi
    return 0
}

function install_blk_archive
{
    cki_debug

    local blk_archive_dir
    local blk_path
    blk_archive_dir=$(basename $BLK_ARCHIVE_REPO)
    blk_path="/tmp/$blk_archive_dir"
    if [ -e "$blk_path" ]; then
        rm -rf "$blk_path"
    fi
    git clone "$BLK_ARCHIVE_REPO" "$blk_path"

    pushd "$blk_path" || return 1
    cargo build --release
    cargo install --path .
    export PATH="$PATH":~/.cargo/bin
    popd || return 1
    return 0
}

function clone_test_suite
{
    cki_debug

    if [ -e "$DMTS_LOCAL" ]; then
        rm -rf "$DMTS_LOCAL"
    fi
    git clone $DMTS_REPO "$DMTS_LOCAL" || return 1

    clone_linux_repo || touch "$DMTS_LOCAL"/LINUX_REPO_UNAVAILABLE

    pushd "$DMTS_LOCAL" || return 1

    python3 -m pip install -r requirements.txt || return 1
    ./dmtest health
    popd || return 1
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

    mnt_metadata=/mnt/dmtest/metadata
    mnt_data=/mnt/dmtest/data

    cki_run "df -h"

    if ! df | grep ${mnt_metadata}; then
        echo "FAIL: Couldn't find metadata device"
        return 1
    fi
    if ! df | grep ${mnt_data}; then
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

    if [ -e "$DMTS_LOCAL"/config.toml ]; then
        rm -f "$DMTS_LOCAL"/config.toml
    fi

    {
        echo "metadata_dev = '${metadata_device}'"
        echo "data_dev = '${data_device}'"
        echo "disable_by_id_check = true"
    } >> "$DMTS_LOCAL"/config.toml


    echo INFO: show "$DMTS_LOCAL"/config.toml
    cat "$DMTS_LOCAL"/config.toml || return 1

    return 0
}

function ts_setup
{
    cki_debug

    install_kernel_devel || return "$CKI_UNINITIATED"
    install_bufio || return "$CKI_UNINITIATED"
    if ! rpm -q dt; then
        install_dt || return "$CKI_UNINITIATED"
    fi
    modprobe dm-thin-pool || return "$CKI_UNINITIATED"
    install_blk_archive || return "$CKI_UNINITIATED"
    clone_test_suite || return "$CKI_UNINITIATED"

    ts_config_setup "$DMTS_LOCAL"/config.toml || return "$CKI_UNINITIATED"

    return "$CKI_PASS"
}
