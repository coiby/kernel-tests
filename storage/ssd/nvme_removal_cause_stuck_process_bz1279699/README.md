# storage/ssd/nvme_removal_cause_stuck_process_bz1279699

Storage: NVMe removal which will cause stuck process and stuck card device node 

## How to run it
Please refer to the top-level README.md for common dependencies.

### Install dependencies
```bash
root# bash ../../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
#### You need run test_devs_setup to define TEST_DEVS
```bash
bash ./runtest.sh
```
