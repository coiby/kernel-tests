# KUNIT test
This is a test wrapper for Kunit.
Based on KUNIT v5.9
Kernel Config requires CONFIG_KUNIT=m & CONFIG_KUNIT_ALL_TESTS=m

Test Maintainer: [Nico Pache](mailto:npache@redhat.com)

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

### support tests
kunit-tests
ext4-inode-test
list-test
sysctl-test
mptcp_crypto_test
mptcp_token_test

### unsupport tests
S390 zfcpdump is not supported

