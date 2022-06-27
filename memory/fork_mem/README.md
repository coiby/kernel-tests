# fork-memory sanity test
Test has three scenarios each of which uses 85% of the free memory by creating \
processes and using some part of memory per process.

The test program takes 3 parameters memory value, iterations and number of child \
processes (tied to number of cpus). A run with default values completes quickly

These default settings can be changed using the yaml file or using \
 --mux-inject  parameter (with avocado run command). The selected values \
 would depend on resources available on the system where the program is executed.

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
