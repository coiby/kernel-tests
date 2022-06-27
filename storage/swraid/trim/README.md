# storage/swraid/trim suite

Test the function of fstrim (TRIM is an Advanced Technology Attachment (ATA)
command that enables an operating system to inform a NAND flash solid-state
drive which data blocks it can erase because they are no longer in use.)
quickly erase invalid data for the RAID that created by mdadm.


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
