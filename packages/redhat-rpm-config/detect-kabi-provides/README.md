# packages/redhat-rpm-config/detect-kabi-provides test
Test for BZ#1004930 (kernel-tools-3.10.0-11.el7.x86_64 requires)

## How to run it
Please refer to the top-level README.md for common dependencies.

### Install dependencies
```bash
root# bash ../../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```
