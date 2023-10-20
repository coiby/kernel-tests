# storage/block/RHEL-11068_failed_to_umount_fs_on_nvme

Storage: failed to umount fs when remove nvme disk and dd hang

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
