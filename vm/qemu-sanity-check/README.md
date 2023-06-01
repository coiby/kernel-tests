# Does the kernel boot on top of qemu-kvm?
Test if the kernel boots on top of qemu-kvm.

Test both KVM and TCG (software emulation).

## How to run it
Please refer to the top-level README.md for common dependencies.

### Install dependencies
```bash
root# bash ../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```
