# ACPI table test suite
Confirm hardware watchdog exists and is functional. \
Disable the watchdog and make sure system reboots as expected.
Test Maintainer: [Rachel Sibley](mailto:rasibley@redhat.com)


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
