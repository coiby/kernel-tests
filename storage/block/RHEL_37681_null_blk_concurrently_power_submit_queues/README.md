# storage/block/RHEL_37681_null_blk_concurrently_power_submit_queues

Storage: Writing 'power' and 'submit_queues' concurrently will trigger kernel panic

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
