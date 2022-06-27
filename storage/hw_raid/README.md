# storage/hw_raid suite

This test generates I/O with FIO at the device level and then trigger a panic.
Additionally performs kexec boot while generating I/O.


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
