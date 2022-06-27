# KUNIT test
This is a test wrapper for Kunit. Supported on Fedora Rawhide, EL8, and C9S.

KUNIT tests are packaged as modules inside the kernel-modules-internals package.

Kernel Config requires CONFIG_KUNIT=m & CONFIG_KUNIT_ALL_TESTS=m

## How to run it
Please refer to the top-level README.md for common dependencies.

### Install dependencies
```bash
root# bash ../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```

### support tests
kunit-test
ext4-inode-test
list-test
sysctl-test
mptcp_crypto_test
mptcp_token_test
bitfield_kunit
cmdline_kunit
property-entry-test
qos-test
resource_kunit
soc-topology-test
string-stream-test
test_linear_ranges
test_bits
test_kasan
time_test
fat_test
lib_test
rational-test
test_list_sort
slub_kunit
memcpy_kunit
dev_addr_lists_test
kfence_test
test_hash

### unsupport tests
S390 zfcpdump is not supported
KCSAN unsupported (cant enable with KASAN)
MCTP unsupported (Not enabled on ark,el,fedora)
S390_MODULES_SANITY_TEST currently disabled but no reason not to enable. TODO.
DAMON (mm) Unsupported (not enabled)

