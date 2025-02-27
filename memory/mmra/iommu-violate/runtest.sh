#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
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
# shellcheck disable=SC1091
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Test name and paths
TEST="memory/mmra/iommu-violate"
TESTPATH=$(pwd)
WORKSPACE="$HOME/iommu-violate"

# Function to install QEMU if not already installed
function install_qemu() {
    # Check if QEMU is already installed
    if type qemu-system-aarch64 &>/dev/null; then
        rlLog "QEMU system 'qemu-system-aarch64' is already installed. Skipping compilation."
        return 0
    fi

    # Compile and install QEMU
    rlLog "QEMU system 'qemu-system-aarch64' not found. Compiling and installing QEMU."
    rm -rf "$WORKSPACE/qemu-9.0.0*"
    wget -nv -P "$WORKSPACE" https://download.qemu.org/qemu-9.0.0.tar.xz || {
        rlLogError "Failed to download the QEMU source code."
        return 1
    }
    tar -xJf "$WORKSPACE/qemu-9.0.0.tar.xz"

    pushd "$WORKSPACE/qemu-9.0.0" || return 1
    ./configure --target-list=$(arch)-softmmu --enable-vhost-user --enable-virtfs --enable-vhost-net --enable-vhost-kernel --enable-slirp || {
        rlLogError "Failed to configure QEMU system."
        return 1
    }
    make -j $(nproc) || {
        rlLogError "Failed to compile QEMU system."
        return 1
    }
    make install || {
        rlLogError "Failed to install QEMU system."
        return 1
    }
    popd

    rlLog "QEMU system 'qemu-system-aarch64' successfully compiled and installed."
    return 0
}

# Function to download the VM image
function download_image() {
    local file image_name base_url

    # Check if the VM image already exists
    file=$(find "$WORKSPACE" -maxdepth 1 -type f -name 'auto-osbuild-qemu-rhivos-*.qcow2' -print)
    if [[ $(echo "$file" | wc -w) -eq 1 ]]; then
        qcow2_image=$file
        rlLog "The image '$qcow2_image' already exists. Skipping download."
        return 0
    fi

    # Remove all related files and start over
    rlLog "Removing existing VM images and related files."
    find "$WORKSPACE" -maxdepth 1 -type f -name 'auto-osbuild-qemu-rhivos-*.qcow2*' -exec rm -rfv {} \;

    # Gather image information
    rlLog "Gathering image information from '/etc/build-info'."
    if [[ ! -f /etc/build-info ]]; then
        rlLogError "Unable to gather image information, '/etc/build-info' not found."
        return 1
    fi

    # Content of a typical /etc/build-info:
    # 	RELEASE="nightly"
    # 	UUID="8326686.cbce78cd"
    # 	TIMESTAMP="2024-06-03 01:00:31.167657"
    # 	IMAGE_NAME="qa"
    # 	IMAGE_MODE="package"
    # 	IMAGE_TARGET="ridesx4"
    rlLog "Content of /etc/build-info:\n$(cat /etc/build-info)"

    # shellcheck disable=SC1091
    source /etc/build-info

    IMAGE_NAME=qa                     # ATC only provide qa regular images
    IMAGE_TYPE=regular
    [[ ${#UUID} -gt 16 ]] && UUID='*' # Support non-toolchain images
    image_name="auto-osbuild-qemu-rhivos-${IMAGE_NAME}-${IMAGE_TYPE:=regular}-$(arch)-${UUID}.qcow2"
    rlLog "The image name to be downloaded is '$image_name'."

    # Download the qcow2 image
    rlLog "Starting download of the qcow2 image."
    base_url="http://rhivos.auto-toolchain.redhat.com/in-vehicle-os-9/RHIVOS-1/${RELEASE_NAME:=latest-RHIVOS-1}/sample-images"
    if [[ $image_name =~ \* ]]; then
        wget --no-verbose -r -p --level 1 -E -e robots=off --cut-dirs=7 -nH --reject='index.html*' --reject='*.png' --reject='*.gif' \
            -P "$WORKSPACE" -A "${image_name}.xz" -A "${image_name}.xz.sha256" "${base_url}"
    else
        wget --no-verbose -P "$WORKSPACE" "${base_url}/${image_name}.xz"
        wget --no-verbose -P "$WORKSPACE" "${base_url}/${image_name}.xz.sha256"
    fi

    # Verify download and checksum
    file=$(find "$WORKSPACE" -maxdepth 1 -type f -name 'auto-osbuild-qemu-rhivos-*.qcow2.xz' -print)
    if [[ $(echo "$file" | wc -w) -ne 1 ]]; then
        rlLog "Downloaded zero or multiple images. Please check the workspace content:"
        ls -la "$WORKSPACE"
        return 1
    fi

    # Verify SHA256 checksum
    find "$WORKSPACE" -maxdepth 1 -type f -name 'auto-osbuild-qemu-rhivos-*.qcow2.xz.sha256' -execdir sha256sum -c {} \; || {
        rlLogError "SHA256 checksum verification failed."
        return 1
    }

    # Decompress the qcow2.xz file
    rlLog "Decompressing the qcow2.xz image file."
    find "$WORKSPACE" -maxdepth 1 -type f -name 'auto-osbuild-qemu-rhivos-*.qcow2.xz' -execdir xz -d {} \; || {
        rlLogError "Failed to decompress the xz file."
        return 1
    }

    # Locate the qcow2 image
    file=$(find "$WORKSPACE" -maxdepth 1 -type f -name 'auto-osbuild-qemu-rhivos-*.qcow2' -print)
    if [[ $(echo "$file" | wc -w) -eq 1 ]]; then
        rlLog "VM image '$file' is downloaded and ready to use."
        return 0
    else
        rlLogError "Failed to locate the qcow2 image."
        return 1
    fi
}

# Function to prepare the drives for the VM
function prepare_vm_drives() {
    rlLog "Preparing the drives for the VM."

    pushd "$WORKSPACE" || return 1

    # Create EFI and VARS images if not already present
    if [[ ! -f ./efi.img ]] || [[ ! -f ./varstore.img ]]; then
        rlLog "Creating EFI and VARS images."
        dd if=/dev/zero of=efi.img bs=1M count=64
        dd if="/usr/share/edk2/aarch64/QEMU_EFI.fd" of=efi.img conv=notrunc
        dd if=/dev/zero of=varstore.img bs=1M count=64
        dd if="/usr/share/edk2/aarch64/QEMU_VARS.fd" of=varstore.img conv=notrunc
        sync
    fi

    popd

    rlLog "VM drives preparation completed."
    return 0
}

# Function to configure the VM credentials
function configure_vm_credential() {
    rlLog "Configuring the credentials for the VM."

    local qcow2_image=$(find "$WORKSPACE" -maxdepth 1 -type f -name 'auto-osbuild-qemu-rhivos-*.qcow2' -print)
    if [[ $(echo "$qcow2_image" | wc -w) -ne 1 ]]; then
        rlLogError "Failed to locate the qcow2 image."
        return 1
    fi

    pushd "$WORKSPACE" || return 1

    # Generate SSH keypair if not already present
    rlLog "Generating SSH keypair."
    [[ ! -f ./vmsshkey ]] && ssh-keygen -q -t rsa -f vmsshkey -N ''

    # Configure SSH profile for the VM
    rlLog "Configuring SSH profile for the VM."
    cat <<EOF >/root/.ssh/config
        Host vm
            HostName localhost
            Port 2222
            User root
            IdentityFile /root/iommu-violate/vmsshkey
            StrictHostKeyChecking no
            UserKnownHostsFile /dev/null
EOF

    # Inject the SSH public key into the VM image
    rlLog "Injecting the SSH public key into the VM image."

    cat >guestfish.cmd <<EOF
        # Copy the public key into the .ssh directory
        copy-in ./vmsshkey.pub /root/.ssh/

        # Append the public key to authorized_keys
        sh "cat /root/.ssh/vmsshkey.pub >> /root/.ssh/authorized_keys"

        # Ensure the permissions are correct
        sh "chown root:root -R /root/.ssh/"
        sh "chmod 700 /root/.ssh"
        sh "chmod 600 /root/.ssh/authorized_keys"

        # Set the correct SELinux context for authorized_keys
        sh "chcon system_u:object_r:ssh_home_t:s0 /root/.ssh/authorized_keys"

        # Modify sshd_config to allow root login
        sh "sed -i 's/^PermitRootLogin .*$/PermitRootLogin yes/' /etc/ssh/sshd_config"

        # Set the correct SELinux context for sshd_config
        sh "chcon system_u:object_r:etc_t:s0 /etc/ssh/sshd_config"

        # List SELinux contexts for sshd_config and authorized_keys
        sh "ls -lZ /root/.ssh/authorized_keys /etc/ssh/sshd_config"

        # Exit guestfish
        exit
EOF

    kill_qemu_process
    export LIBGUESTFS_BACKEND=direct
    export SUPERMIN_KERNEL=/boot/vmlinuz-$(uname -r)
    export SUPERMIN_MODULES=/lib/modules/$(uname -r)
    guestfish --rw -a "$qcow2_image" -m /dev/sda3 -f guestfish.cmd || {
        rlLogError "Failed to inject the SSH key into the VM image."
        return 1
    }

    popd

    rlLog "VM credentials configured successfully."
    return 0
}

# Function to start the VM
function start_vm() {
    rlLog "Starting the VM."

    local qcow2_image=$(find "$WORKSPACE" -maxdepth 1 -type f -name 'auto-osbuild-qemu-rhivos-*.qcow2' -print)
    if [[ $(echo "$qcow2_image" | wc -w) -ne 1 ]]; then
        rlLogError "Failed to locate the qcow2 image."
        return 1
    fi

    local pname=qemu-system-aarch64
    local qemucmd="$pname -machine virt -cpu cortex-a53 -smp 4 -m 1G -nographic \
                    -drive if=pflash,format=raw,file=efi.img,readonly=on \
                    -drive if=pflash,format=raw,file=varstore.img \
                    -drive file=${qcow2_image},index=0,media=disk,format=qcow2,if=virtio,snapshot=off \
                    -device virtio-net-pci,netdev=n0 \
                    -netdev user,id=n0,hostfwd=tcp::2222-:22 \
                    -device virtio-iommu,aw-bits=48 \
                    -device edu,dma_mask=0xffffffffffffffff"
    rlLog "QEMU command: $(echo "$qemucmd" | xargs)"

    rlLog "Initializing the VM."
    pushd "$WORKSPACE" || return 1
    rm -rf ./qemu.log
    screen -dmS qemu_session bash -c "$qemucmd &>./qemu.log"
    sleep 5
    popd

    if pidof "$pname" &>/dev/null; then
        rlLog "The VM has started successfully."
        return 0
    else
        rlLogError "Failed to start the VM."
        return 1
    fi
}

# Function to stop the VM
function stop_vm() {
    rlLog "Stopping the VM."

    local pname=qemu-system-aarch64
    local pid=$(pidof "$pname")

    rlLog "Sending poweroff signal to the VM."
    ssh vm poweroff

    rlLog "Waiting for the VM to stop."
    for ((i = 1; i <= 60; i++)); do
        sleep 1
        if [[ -n "$pid" ]]; then
            rlLog "$(date): The $pname process is still running, PID: $pid"
        else
            rlLog "$(date): The $pname process has stopped."
            break
        fi
        pid=$(pidof "$pname")
    done
    if [[ -n "$pid" ]]; then
        rlLogError "$(date): Failed to stop the VM after 1 minute."
        return 1
    else
        rlLog "$(date): Successfully stopped the VM within 1 minute."
        return 0
    fi
}

# Function to attempt connecting to the VM
function try_connect_vm() {
    rlLog "Attempting to connect to the VM."

    for ((i = 1; i <= 10; i++)); do
        sleep 30
        rlLog "$(date): Attempt $i of 10 to connect to the VM."
        ssh vm 'who -b' && break
    done
    if [[ $i -le 10 ]]; then
        rlLog "$(date): Successfully connected to the VM after $i attempts."
        return 0
    else
        rlLogError "$(date): Failed to connect to the VM after $i attempts."
        return 1
    fi
}

# Function to kill QEMU process
function kill_qemu_process() {
    local pname=qemu-system-aarch64
    local pid=$(pidof "$pname")

    rlLog "Killing the $pname process."
    if [[ -n "$pid" ]]; then
        rlLog "Killing the $pname process, PID: $pid"
        killall -9 "$pname"
        sleep 5
        sync

        # Check if the process is still running
        pid=$(pidof "$pname")
        if [[ -n "$pid" ]]; then
            rlLogError "The $pname process is still running, PID: $pid"
            return 1
        else
            rlLog "The $pname process has been successfully terminated."
            return 0
        fi
    else
        rlLog "No $pname process is running, skipping."
        return 0
    fi
}

rlJournalStart

# Check if the current kernel version matches the RHIVOS environment pattern
rlShowRunningKernel
if ! (uname -r | grep -w -q 'el[0-9]*iv'); then
    rlLog "Skipping $TEST: This test is intended to run only in the RHIVOS environment."
    rstrnt-report-result "$TEST" SKIP
    rlJournalEnd
    exit 0
fi

rlPhaseStartSetup

# Create and enter the workspace
mkdir -p "$WORKSPACE" && cd "$WORKSPACE"

error_msg="$WORKSPACE/error_msg.txt"
rm -rf "$error_msg"

# Install the QEMU system (required packages: ninja-build, make, gcc, libslirp, libslirp-devel)
(install_qemu || echo "Failed to install the QEMU system." >>"$error_msg") &

# Download the VM image
(download_image || echo "Failed to download the VM image." >>"$error_msg") &

# Prepare the drives for the VM (required packages: edk2-aarch64)
(prepare_vm_drives || echo "Failed to prepare the drives for the VM." >>"$error_msg") &

# Wait for above processes to complete
wait && [[ -f $error_msg ]] && rlDie "$(cat "$error_msg")"

# Configure the credentials (required packages: libguestfs)
configure_vm_credential || rlDie "Failed to configure the credentials."

# Power on the VM (required packages: screen)
start_vm || rlDie

try_connect_vm || rlDie

rlPhaseEnd

rlPhaseStartTest

cd "$WORKSPACE"

# Verify the kernel version of the VM
rlLog "Verifying the kernel version of the VM."
kernel_version_vm="$(ssh vm 'uname -r')"
rlLog "Kernel version of the VM   : $kernel_version_vm"
rlLog "Kernel version of the Host : $(uname -r)"
if [[ "$kernel_version_vm" != "$(uname -r)" ]]; then
    rlLog "Skipping $TEST: the kernel version in the VM does not match the host's version."
    rstrnt-report-result "$TEST" SKIP
    rlDie
fi

# Verify the IOMMU is running in Translated mode
rlLog "Verifying the IOMMU is running in Translated mode."
rlRun "ssh vm 'dmesg | grep \"iommu: Default domain type: Translated\"'" 0 "IOMMU should run in Translated Mode on the VM."
rlRun "ssh vm 'grep -w DMA /sys/kernel/iommu_groups/*/type'" 0 "IOMMU should run in Translated Mode on the VM."

# Setup the Root Certificate on the VM
rlLog "Setting up the Root Certificate on the VM."
if ssh vm '[ -f /etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt ]'; then
    rlLog "The Root Certificate already exists on the VM, skipping setup."
else
    rlLog "Setting up the Root Certificate on the VM."
    rlAssertExists "/etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt"
    rlRun "scp /etc/pki/ca-trust/source/anchors/* vm:/etc/pki/ca-trust/source/anchors/"
    rlRun "ssh vm 'update-ca-trust extract'"
    if ssh vm '[ -f /etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt ]'; then
        rlLog "The Root Certificate on the VM is ready for use."
    else
        rlDie "Failed to set up the Root Certificate on the VM."
    fi
fi

# Setup the DNF Repositories on the VM
rlLog "Setting up the DNF Repositories on the VM."
if ssh vm "ls /etc/yum.repos.d/synced &>/dev/null"; then
    rlLog "DNF repositories on the VM are already synced with the host, skipping setup."
else
    rlRun "ssh vm 'rm -rf /etc/yum.repos.d/*.repo'"
    rlRun "scp /etc/yum.repos.d/*.repo vm:/etc/yum.repos.d/"
    rlRun "ssh vm 'dnf clean all && dnf makecache --nogpgcheck && touch /etc/yum.repos.d/synced'"
fi

# Upload the cmdline_helper to the VM
rlLog "Uploading the cmdline_helper to the VM."
rlAssertExists "$TESTPATH/../../../cmdline_helper/libcmd.sh"
rlAssertExists "$TESTPATH/../../../cki_lib/libcki.sh"
rlRun "ssh vm 'mkdir -p /root/cmdline_helper/ /root/cki_lib/'"
rlRun "scp $TESTPATH/../../../cmdline_helper/libcmd.sh vm:/root/cmdline_helper/"
rlRun "scp $TESTPATH/../../../cki_lib/libcki.sh vm:/root/cki_lib/"

# Enable installing unsigned kernel modules on the VM
rlLog "Enabling installation of unsigned kernel modules on the VM."
if ssh vm "cat /proc/cmdline" | grep -q "module.sig_enforce=1"; then
    rlLog "Enabling installation of unsigned kernel modules on the VM."
    rlRun "ssh vm 'dnf install -y grubby'"
    rlRun "ssh vm 'source /root/cmdline_helper/libcmd.sh; change_cmdline \"-module.sig_enforce=1\"'"
    rlRun "ssh vm 'reboot'" 0 "Rebooting the VM to apply cmdline changes."
    try_connect_vm || rlDie
else
    rlLog "Installation of unsigned kernel modules on the VM is already enabled, skipping."
fi
if ssh vm "cat /proc/cmdline" | grep -q "module.sig_enforce=1"; then
    rlDie "Failed to enable installation of unsigned kernel modules on the VM."
else
    rlLog "The VM is ready to install unsigned kernel modules."
fi

# Upload the hardware device driver to the VM
rlLog "Uploading the hardware device driver to the VM."
rlAssertExists "$TESTPATH/src/edu_driver.c"
rlAssertExists "$TESTPATH/src/Kbuild"
rlAssertExists "$TESTPATH/src/Makefile"
rlRun "scp -r $TESTPATH/src vm:/root/"

# Compile the hardware device driver on the VM
rlLog "Compiling the hardware device driver on the VM."
rlRun "ssh vm 'dnf install -y make gcc kernel-automotive-devel-\$(uname -r)'"
rlRun "ssh vm 'cd /root/src && make -j \$(nproc)'" || rlDie "Failed to compile the hardware device driver"

# Install the hardware device driver on the VM
rlLog "Installing the hardware device driver on the VM."
rlRun -l -s "ssh vm 'dmesg -C; insmod /root/src/edu_driver.ko; dmesg'"
# shellcheck disable=SC2154
rlAssertGrep "edu_driver module initializing" "$rlRun_LOG"

# Test 1: Cause a hardware device to attempt to access an invalid page of the address space and confirm this results in graceful failure
rlLog "Test 1: Access an invalid page of the address space and confirm graceful failure."
rlRun -l -s "ssh vm 'dmesg -C; echo -n \"test_invalid\" > /sys/kernel/debug/edu_driver/edu_driver_test_1; dmesg'"
rlAssertGrep "TEST: test_write_read_dma_with_fault_on_invalid (page fault is expected)" "$rlRun_LOG"
rlAssertGrep "virtio_iommu virtio0: page fault from EP [[:digit:]]* at 0xaabbccddeeff00 \[\]" "$rlRun_LOG"

# Test 2: Cause a hardware device to attempt to access a read-only page of the address space and confirm this results in graceful failure
rlLog "Test 2: Access a read-only page of the address space and confirm graceful failure."
rlRun -l -s "ssh vm 'dmesg -C; echo -n \"test_read_only\" > /sys/kernel/debug/edu_driver/edu_driver_test_1; dmesg'"
rlAssertGrep "TEST: test_write_read_dma_with_fault_on_readonly (page fault is expected)" "$rlRun_LOG"
rlAssertGrep "virtio_iommu virtio0: page fault from EP [[:digit:]]* at 0x[[:xdigit:]]* \[W\]" "$rlRun_LOG"

# Test 3: Cause a hardware device to attempt to access an unmapped page of the address space and confirm this results in graceful failure
rlLog "Test 3: Access an unmapped page of the address space and confirm graceful failure."
rlRun -l -s "ssh vm 'dmesg -C; echo -n \"test_unmapped\" > /sys/kernel/debug/edu_driver/edu_driver_test_1; dmesg'"
rlAssertGrep "TEST: test_write_read_dma_with_fault_on_unmapped (page fault is expected)" "$rlRun_LOG"
rlAssertGrep "virtio_iommu virtio0: page fault from EP [[:digit:]]* at 0x[[:xdigit:]]* \[\]" "$rlRun_LOG"

# Remove the hardware device driver on the VM
rlLog "Removing the hardware device driver from the VM."
rlRun -l -s "ssh vm 'dmesg -C; rmmod edu_driver; dmesg'"
rlAssertGrep "edu_driver module exiting" "$rlRun_LOG"

rlPhaseEnd

rlPhaseStartCleanup

# Power off the VM
stop_vm || kill_qemu_process

# Submit the QEMU log file
rlFileSubmit ./qemu.log

rlPhaseEnd

rlJournalEnd

rlJournalPrintText
