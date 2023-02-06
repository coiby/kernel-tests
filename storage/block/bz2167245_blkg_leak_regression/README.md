# storage/block/bz2167245_blkg_leak_regression

Storage: request queue won't be freed if the queue/disk is in blk root cgroup

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
