# storage/ssd/nvme_mq_io_stress_testing

Storage: NVMe SSD mq io stress testing with Iozone/dt/fio 

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
