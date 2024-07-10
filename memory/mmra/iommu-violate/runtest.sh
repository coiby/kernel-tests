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

TEST="memory/mmra/iommu-violate"
TESTPATH=$(pwd)
WORKSPACE="$HOME/iommu-violate"

function start_vm() {
    local pname=qemu-system-aarch64
    local qemucmd="$pname -machine virt -cpu cortex-a53 -smp 4 -m 8G -nographic \
                    -drive if=pflash,format=raw,file=efi.img,readonly=on \
                    -drive if=pflash,format=raw,file=varstore.img \
                    -drive file=${qcow2_image},index=0,media=disk,format=qcow2,if=virtio,snapshot=off \
                    -device virtio-net-pci,netdev=n0 \
                    -netdev user,id=n0,hostfwd=tcp::2222-:22 \
                    -device virtio-iommu,aw-bits=48 \
                    -device edu,dma_mask=0xffffffffffffffff"
    rlLog "QEMU command: $(echo "$qemucmd" | xargs)"

    rlLog "Starting the VM."
    pushd "$WORKSPACE"
    rm -rf ./qemu.log
    screen -dmS qemu_session bash -c "$qemucmd &>./qemu.log"
    sleep 5
    popd

    if pidof "$pname"; then
        rlLog "The VM is started."
        return 0
    else
        rlLogError "Failed to start the VM."
        return 1
    fi
}

function stop_vm() {
    local pname=qemu-system-aarch64
    local pid=$(pidof "$pname")

    rlLog "Stopping the VM."
    ssh vm poweroff

    rlLog "Waiting the VM to be stopped."
    for ((i = 1; i <= 60; i++)); do
        sleep 1
        if [[ -n "$pid" ]]; then
            rlLog "$(date): The $pname process is still running, PID: $pid"
        else
            rlLog "$(date): The $pname process is stopped."
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

function kill_qemu_process() {
    local pname=qemu-system-aarch64
    local pid=$(pidof "$pname")

    rlLog "Kill the $pname process."
    if [[ -n "$pid" ]]; then
        # Kill the process
        rlLog "Killing the $pname process, PID: $pid"
        killall -9 "$pname"
        sleep 5
        sync

        # Check the results
        pid=$(pidof "$pname")
        if [[ -n "$pid" ]]; then
            rlLogError "The $pname process is still running, PID: $pid"
            return 1
        else
            rlLog "The $pname process has been killed successfully."
            return 0
        fi
    else
        rlLog "No $pname process is running, skip."
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

        # Compile the QEMU system (required packages: ninja-build, make, gcc, libslirp, libslirp-devel)
        rlLog "Starting QEMU system compilation process."

        # Check if the QEMU system is already installed
        if type qemu-system-aarch64; then
            rlLog "QEMU system 'qemu-system-aarch64' is already installed. Skipping compilation."
        else
            rlLog "QEMU system 'qemu-system-aarch64' is not installed. Compiling now."
            cd "$WORKSPACE"
            rm -rf ./qemu-9.0.0*
            wget https://download.qemu.org/qemu-9.0.0.tar.xz || rlDie "Failed to download the source code."
            tar -xJf ./qemu-9.0.0.tar.xz

            cd qemu-9.0.0
            ./configure --target-list=$(arch)-softmmu --enable-vhost-user --enable-virtfs --enable-vhost-net --enable-vhost-kernel --enable-slirp || rlDie "Failed to configure QEMU system."
            make -j $(nproc) || rlDie "Failed to compile QEMU system."
            make install || rlDie "Failed to install QEMU system."

            rlLog "QEMU system 'qemu-system-aarch64' is now compiled and ready to use."
        fi

        # Download and prepare the VM image
        rlLog "Starting the process to download and prepare the VM image."

        if [[ -f /etc/build-info ]]; then
            # shellcheck disable=SC1091
            source /etc/build-info
            IMAGE_NAME=developer # Workaround: always using developer images
            qcow2_image="auto-osbuild-qemu-rhivos9-${IMAGE_NAME}-${IMAGE_TYPE:=regular}-$(arch)-${UUID}.qcow2"
            qcow2_image_url="http://rhivos.auto-toolchain.redhat.com/in-vehicle-os-9/${RELEASE:=nightly}/sample-images/${qcow2_image}.xz"
        else
            rlDie "Failed to read the /etc/bufild-info file."
        fi

        # Check if the VM image already exists
        cd "$WORKSPACE"
        if [ -f "$qcow2_image" ]; then
            rlLog "VM image '$qcow2_image' already exists. Skipping download."
        else
            rlLog "VM image '$qcow2_image' not found. Downloading it now."
            wget "$qcow2_image_url" || rlDie "Failed to download the VM image from '$qcow2_image_url'."
            if wget "${qcow2_image_url}.sha256"; then
                sha256sum -c "$qcow2_image.xz.sha256" || rlDie "SHA256 checksum verification failed."
            fi
            xz -d "$qcow2_image.xz" || rlDie "Failed to decompress the xz file."
            rlLog "VM image '$qcow2_image' is downloaded and ready to use."
        fi

        # Configure the SSH key (required packages: libguestfs)
        cd "$WORKSPACE"
        rlLog "Generating the SSH keypair."
        [[ ! -f ./vmsshkey ]] && ssh-keygen -q -t rsa -f vmsshkey -N ''

        kill_qemu_process

        rlLog "Injecting the SSH Public Key into the VM image."
        export LIBGUESTFS_BACKEND=direct

        cat > guestfish.cmd << EOF
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

        guestfish --rw -a "$qcow2_image" -m /dev/sda3 -f guestfish.cmd || rlDie "Failed to inject the SSH key into the VM image."

        # Prepare the drives for the VM (required packages: edk2-aarch64)
        rlLog "Preparing the drives for the VM."

        cd "$WORKSPACE"
        if [[ ! -f ./efi.img ]] || [[ ! -f ./varstore.img ]]; then
            dd if=/dev/zero of=efi.img bs=1M count=64
            dd if="/usr/share/edk2/aarch64/QEMU_EFI.fd" of=efi.img conv=notrunc
            dd if=/dev/zero of=varstore.img bs=1M count=64
            dd if="/usr/share/edk2/aarch64/QEMU_VARS.fd" of=varstore.img conv=notrunc
            sync
        fi

        # Power on the VM (required packages: screen)
        start_vm || rlDie

        # Connect to the VM
        cat <<EOF >/root/.ssh/config
        Host vm
            HostName localhost
            Port 2222
            User root
            IdentityFile /root/iommu-violate/vmsshkey
            StrictHostKeyChecking no
            UserKnownHostsFile /dev/null
EOF

        try_connect_vm || rlDie

    rlPhaseEnd

    rlPhaseStartTest

        cd "$WORKSPACE"

        # Verify the kernel version of the VM
        rlLog "Verifying the VM."
        rlAssertEquals "The VM should have the same kernel version as the host." "$(ssh vm 'uname -r')" "$(uname -r)" || rlDie

        # Verify the IOMMU is running in the Translated mode
        rlLog "Verifying the IOMMU is running in the Translated mode."
        rlRun "ssh vm 'dmesg | grep \"iommu: Default domain type: Translated\"'" 0 "IOMMU should run in Translated Mode on the VM."
        rlRun "ssh vm 'grep -w DMA /sys/kernel/iommu_groups/*/type'" 0 "IOMMU should run in Translated Mode on the VM."

        # Setup the Root Certificate on the VM
        rlLog "Setup the Root Certificate on the VM."
        if ssh vm '[ -f /etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt ]'; then
            rlLog "The Root Certificate already exists on the VM, skip."
        else
            rlLog "Setting up the Root Certificate on the VM."
            rlAssertExists "/etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt"
            rlRun "scp /etc/pki/ca-trust/source/anchors/* vm:/etc/pki/ca-trust/source/anchors/"
            rlRun "ssh vm 'update-ca-trust extract'"
            if ssh vm '[ -f /etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt ]'; then
                rlLog "The Root Certificate on the VM is ready to use."
            else
                rlDie "Failed to setup the Root Certificate on the VM."
            fi
        fi

        # Setup the DNF Repos on the VM
        rlLog "Setting up the DNF Repositories on the VM."
        rlRun "ssh vm 'rm -rf /etc/yum.repos.d/*.repo'"
        rlRun "scp /etc/yum.repos.d/*.repo vm:/etc/yum.repos.d/"
        rlRun "ssh vm 'dnf clean all && dnf makecache --nogpgcheck'"

        # Upload the cmdline_helper to the VM
        rlLog "Uploading the cmdline_helper to the VM."
        rlAssertExists "$TESTPATH/../../../cmdline_helper/libcmd.sh"
        rlAssertExists "$TESTPATH/../../../cki_lib/libcki.sh"
        rlRun "ssh vm 'mkdir -p /root/cmdline_helper/ /root/cki_lib/'"
        rlRun "scp $TESTPATH/../../../cmdline_helper/libcmd.sh vm:/root/cmdline_helper/"
        rlRun "scp $TESTPATH/../../../cki_lib/libcki.sh vm:/root/cki_lib/"

        # Enable installing unsigned kernel modules on the VM
        rlLog "Enable installing unsigned kernel modules on the VM."
        if ssh vm "cat /proc/cmdline" | grep -q "module.sig_enforce=1"; then
            rlLog "Enabling installing unsigned kernel modules on the VM."
            rlRun "ssh vm 'dnf install -y grubby'"
            rlRun "ssh vm 'source /root/cmdline_helper/libcmd.sh; change_cmdline \"-module.sig_enforce=1\"'"
            rlRun "ssh vm 'reboot'" 0 "Reboot the VM to make change_cmdline take effect"
            try_connect_vm || rlDie
        else
            rlLog "Installing unsigned kernel modules on the VM is already enabled, skip."
        fi
        if ssh vm "cat /proc/cmdline" | grep -q "module.sig_enforce=1"; then
            rlDie "Failed to enable installing unsigned kernel modules on the VM."
        else
            rlLog "The VM is ready to install unsigned kernel modules."
        fi

        # Upload the hardware device driver to the VM
        rlLog "Uploading the hardware device driver to the VM."
        rlAssertExists "$TESTPATH/src/edu_driver.c"
        rlAssertExists "$TESTPATH/src/Kbuild"
        rlAssertExists "$TESTPATH/src/Makefile"
        rlRun "scp -r $TESTPATH/src vm:/root/"

        # Complile the hardware device driver on the VM
        rlLog "Compliling the hardware device driver on the VM."
        rlRun "ssh vm 'dnf install -y make gcc kernel-automotive-devel-\$(uname -r)'"
        rlRun "ssh vm 'cd /root/src && make -j \$(nproc)'" || rlDie "Failed to complile the hardware device driver"

        # Install the hardware device driver on the VM
        rlLog "Installing the hardware device driver on the VM."
        rlRun -l -s "ssh vm 'dmesg -C; insmod /root/src/edu_driver.ko; dmesg'"
        # shellcheck disable=SC2154
        rlAssertGrep "edu_driver module initializing" "$rlRun_LOG"

        # Test 1: Cause a hardware device to attempt to access an invalid page of the address space and confirm this results in graceful failure
        rlLog "Test 1: Cause a hardware device to attempt to access an invalid page of the address space and confirm this results in graceful failure"
        rlRun -l -s "ssh vm 'dmesg -C; echo -n \"test_invalid\" > /sys/kernel/debug/edu_driver/edu_driver_test_1; dmesg'"
        rlAssertGrep "TEST: test_write_read_dma_with_fault_on_invalid (page fault is expected)" "$rlRun_LOG"
        rlAssertGrep "virtio_iommu virtio0: page fault from EP [[:digit:]]* at 0xaabbccddeeff00 \[\]" "$rlRun_LOG"

        # Test 2: Cause a hardware device to attempt to access an read-only page of the address space and confirm this results in graceful failure
        rlLog "Test 2: Cause a hardware device to attempt to access an read-only page of the address space and confirm this results in graceful failure"
        rlRun -l -s "ssh vm 'dmesg -C; echo -n \"test_read_only\" > /sys/kernel/debug/edu_driver/edu_driver_test_1; dmesg'"
        rlAssertGrep "TEST: test_write_read_dma_with_fault_on_readonly (page fault is expected)" "$rlRun_LOG"
        rlAssertGrep "virtio_iommu virtio0: page fault from EP [[:digit:]]* at 0x[[:xdigit:]]* \[W\]" "$rlRun_LOG"

        # Test 3: Cause a hardware device to attempt to access an unmapped page of the address space and confirm this results in graceful failure
        rlLog "Test 3: Cause a hardware device to attempt to access an unmapped page of the address space and confirm this results in graceful failure"
        rlRun -l -s "ssh vm 'dmesg -C; echo -n \"test_unmapped\" > /sys/kernel/debug/edu_driver/edu_driver_test_1; dmesg'"
        rlAssertGrep "TEST: test_write_read_dma_with_fault_on_unmapped (page fault is expected)" "$rlRun_LOG"
        rlAssertGrep "virtio_iommu virtio0: page fault from EP [[:digit:]]* at 0x[[:xdigit:]]* \[\]" "$rlRun_LOG"

        # Remove the hardware device driver on the VM
        rlLog "Removing the hardware device driver on the VM."
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
