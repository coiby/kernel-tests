# storage/iscsi/params suite
Testing various iSCSI parameters values on local LIO target and iSCSI initiator.  
The source code can be found at [python-stqe](https://gitlab.com/rh-kernel-stqe/python-stqe).  
Test Maintainer: [Martin Hoyer](mailto:mhoyer@redhat.com)

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
