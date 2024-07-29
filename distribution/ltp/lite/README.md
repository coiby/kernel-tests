# LTP lite testsuite
LTP lite testsuite can be used to run a subset tests in the LTP testsuite that contains collection of tools for testing the Linux kernel, and for a quick test to check an installed base.

## How to run it
Please refer to the top-level README.md for common dependencies. Test-specific dependencies will automatically be installed when executing 'make run'. For a complete detail, see https://github.com/linux-test-project/ltp. 

Unless specified through the $RUNTESTS variable, this test suite defaults to test "RHELKT1LITE", with input parameters derived from a configuration file from https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/tree/main/distribution/ltp/lite/configs 

### Install dependencies
```bash
root# bash ../../../cki_bin/pkgs_install.sh metadata
```

### Test inputs
```
$RUNTESTS, defaults to 'RHELKT1LITE'.
```

### Execute the test
```bash
bash ./runtest.sh
```

### Results location
```
output.txt | taskout.log, log is dependent upon the test executor utilized.
$RUNTESTS.FILTERED.run.log, defaults to 'RHELKT1LITE.FILTERED.run.log'
```

### Expected result
```
output.txt | taskout.log
    INFO: ltp-pan reported all tests PASS

$RUNTESTS.FILTERED.run.log
    Approximately 1200 test suites are executed as part of the default RHELKT1LITE.
    Independent test suite execution results are reported in the log in the following format:
        Summary:
        passed   x
        failed   x
        broken   x
        skipped  x
        warnings x
```
