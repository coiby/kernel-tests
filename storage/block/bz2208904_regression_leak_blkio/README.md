# storage/block/bz2208904_regression_leak_blkio

Storage: Regression of 3b8cc6298724 ("blk-cgroup: Optimize blkcg_rstat_flush()")

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
