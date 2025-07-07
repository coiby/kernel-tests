# Syzkaller wrapper

This tool is intended to be used in fuzzing tests.
It supports both single and multi host environments, depending on the test plan.

Create your test fmf file, and set these mandatory fields:

```yaml
path: /syzkaller
test: bash runtest.sh
require:
  - make
  - golang
  - gcc
  - glibc
  - glibc-common
  - glibc-devel
  - gcc-c++
  - wget
  - git
  - patch
  - type: file
    pattern:
        - /kernel-include
        - /syzkaller
environment:
    # List of syscalls to fuzz
    main_syscalls: [syscalls-list]
    # List of system calls that should be treated as disabled (optional)
    disable_syscalls: [syscalls-list]
    # List of syscalls that should not be mutated by the fuzzer (optional)
    support_syscalls: [syscalls-list]
    # Fuzzing time in seconds
    time: 1200
duration: 1h # set according to fuzzing time + build time, build time is no less than 30 minutes
```

See `generic.fmf` for details and examples.

For multihost testing you will also need a multihost test plan. Example, for a manual run:

```yaml
environment+:
  DUT_HOSTNAME: # a board you have reserved
  VM_HOSTNAME: # a VM you have reserved

discover+:
  - name: external_fuzzing
    url: your_test_repo
    ref: your_test_repo_branch
    how: fmf
    test:
      - /syzkaller/generic # set it to your test fmf, or use generic if you are just playing around
    where:
      - server

provision:
  - name: server
    role: server
    how: connect
    guest: $VM_HOSTNAME
    user: root # you should have ssh publickey access to your VM

  - name: client
    role: client
    how: connect
    guest: $DUT_HOSTNAME
    user: root
    password: password # boards typically use root/password credentials to log in

prepare+:
    # glibc is also required in client for syzkaller to work
  - name: Install additional packages
    how: install
    package:
      - glibc
      - glibc-common
      - glibc-devel
    where:
      - client
```

Multihost test plan for a Testing-Farm run:

```yaml
summary: multihost syzkaller fuzzing test plan

discover+:
  - name: external_fuzzing
    url: https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests.git
    ref: main
    how: fmf
    test:
      - /syzkaller/generic
    where:
      - server

provision:
  - name: server
    role: server
    image: $vm_compose # set in TF CLI command
    arch: aarch64

  - name: client
    role: client
    how: artemis
    api-url: http://url/to/artemis
    pool: $dut_pool # set in TF CLI command
    arch: aarch64
    image: "$board_compose" # set in TF CLI command
    keyname: master-key
    provision-timeout: 86400
    user: root
    password: password

prepare+:
  - name: Install dependencies on client
    how: install
    package:
      - gcc
      - gcc-c++
      - git
      - glibc
      - glibc-common
      - glibc-devel
      - make
      - patch
      - sshpass
      - tar
      - wget
    where:
      - client
```

TF CLI command example:
```shell
compose=auto-osbuild-rcar_s4-rhivos-qa-regular-aarch64-11871884.9e62a45d
vm_compose=auto-osbuild-qemu-rhivos-qa-regular-aarch64-11871884.9e62a45d
disk_checksum="https://url/to/image.raw.xz.sha256"
disk_image="https://url/to/image.raw.xz"
image_type=regular
board_compose="{\"disk_checksum\":\"$disk_checksum\",\"disk_image\":\"$disk_image\"}"
dut_pool=rcar-s4-atc
hw_target=rcar_s4

release_name=RHIVOS-1.0.0-RC3
scenario=er

testing-farm request \
    -t ArtemisOneShotOnly=True \
    --pipeline-type tmt-multihost \
    --arch aarch64 \
    --compose ${compose} \
    --git-url https://test/plan/repository.git \
    --plan /fuzzing/test/plan/path \
    -e RELEASE_NAME=${release_name} \
    -e HW_TARGET=rcar_s4 \
    -e IMAGE_KEY=${compose} \
    -e dut_pool=${dut_pool} \
    -e board_compose=${board_compose} \
    -e vm_compose=${vm_compose} \
    -c scenario=${scenario} \
    -c hw_target=${hw_target} \
    -c image_type=${image_type} \
    --timeout 5760
```

## Fuzzing in QM

- **Multihost testing is not supported for this mode**.
- Set `FUZZ_IN_QM` environment variable.
- Check SELinux policies required. Current file `syz_bpf_mounton` was created/installed with the following commands:

```bash
ausearch -m avc -ts recent | audit2allow -M syz_bpf_mounton
semodule -i syz_bpf_mounton.pp
```

- Test cleanup phase removes the policy with

```bash
semodule -r syz_bpf_mounton
```
