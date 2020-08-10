# LTP upstream lite testsuite
LTP upstream lite testsuite can be used to run a subset tests in the LTP testsuite that contains collection of tools for testing the Linux kernel, and for a quick test to check an installed base. The testsuite runs on Beaker upstream testing only. \
Test Maintainer: [Memory Management](mailto:mm-qe@redhat.com)

## How to run it
Please refer to the top-level README.md for common dependencies. For a complete detail, see https://github.com/linux-test-project/ltp. 

### Install dependencies
```bash
root# bash ../../../cki_bin/pkgs_install.sh metadata
```
### Execute the test
```bash
$ bash ./runtest.sh
```
