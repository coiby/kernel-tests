# module-load test
This test is designed to test basic kernel functionality.
It loads some kernel modules from a list of modules in a file and checks to see, if they have loaded and can be removed.

## How to run it

### Dependencies
Please refer to the top-leve README.md for common dependencies.

### Install dependencies
```bash
root# bash ../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```
