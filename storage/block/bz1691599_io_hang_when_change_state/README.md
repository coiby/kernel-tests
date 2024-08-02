# storage/block/bz1691599_io_hang_when_change_state

Storage: IO hang during setting device state as blocked and resetting it to running

## Note

Can not change state from userspace after rhel8

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
