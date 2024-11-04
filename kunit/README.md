# KUNIT test
This is a test wrapper for KUNIT using beakerlib and restraint.

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

### Configure Enviornment Variables
```
SKIP_TESTS: allows for a list of tests to skip (module name)

```

