# kselftest test
This is a test wrapper for [kernel selftest](https://github.com/torvalds/linux/tree/master/tools/testing/selftests) to be run in beaker test environment.

Test Maintainer:	[Hangbin Liu](mailto:haliu@redhat.com)
			[Stephen Bertram](mailto:sbertram@redhat.com)

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
all

### VARIABLES
BUILD_FROM_SRC      Indicates if this is a test run using that will build the harness.
deault none

UPSTREAM_SOURCE_URL Indicates location of upstream test source tar file.
deault none

DELIVERED_TESTS     Indicates if this is a test run using the pre compiled internal harness.
default none

TEST_ITEMS 		Set of test collections you want to execute. e.g. "bpf net kvm".
default "default" (not a valid collection and will fail if DELIVERED_TESTS is not set )

CKI_SELFTESTS_URL 	CKI Upstream latest tar build.
default none

SKIP_TARGETS 		List of selftests to skip. This list must be in test format "collection:test". At this time it does not support skipping a whole collection. e.g. "bpf:test_progs net:tls netfilter:nft_trans_stress.sh".
default none

INCLUDE			Include any files with special variables or function definitions.
default none

### Usage

The wrapper allows you to run your tests with four suites. 
- One option is the pre-built package that comes with the kernel under test and is selected by setting variable DELIVERED_TESTS. This is restricted because not all selftests are built and so not delivered with selftests-internal.
- The second option is the pre-built upstream package and is selected by setting CKI_SELFTESTS_URL which needs to be the fully qualified path to the tar release. You will need to provide the collection(s) to be tested by setting TEST_ITEMS to that collection(s). At least one needs to be provided and if multiple collections, each collection must be separated by a space.
- The third option is the upstream source package and is selected by setting BUILD_FROM_SRC and UPSTREAM_SOURCE_URL which needs to be the fully qualified path to the tar release. You will need to provide the collection(s) to be tested by setting TEST_ITEMS to that collection(s). At least one needs to be provided and if multiple collections, each collection must be separated by a space.
- Final option is to build and install kselftests from the source of the kernel under test. This is selected by setting BUILD_FROM_SRC and not setting UPSTREAM_SOURCE_URL. You will need to provide the collection(s) to be tested by setting TEST_ITEMS to that collection(s). At least one needs to be provided and if multiple collections, each collection must be separated by a space.

Allowance for custom functions
- If you need to run special setup for your tests you will need to create a function with the name `do_<collection>_config` that should be defined in your include file.
- If you need to patch or cleanup after your specific collection, similar provisions have been made to accommodate using `do_<collection>_patch` and `do_<collection>_reset`.
- Patch for all collections is applied before the harness is built. Setup and reset for each collection is executed before and after each collection is executed.

1. - TODO: At this time there is no support for individual tests being part of TEST_ITEMS. A crude workaround would be to add all tests you want to skip to SKIP_TARGETS, leaving only the tests you want to run in the collection not skipped.
1. - TODO: At this time there is no support for collections being part of SKIP_TARGETS. This is only a potential issue with pre-built package delivered with the kernel. Currently when BUILD_FROM_SRC is set to 2 the script ignores TEST_ITEMS. A crude workaround would be to select all tests from the collection you want to skip and include them in SKIP_TARGETS.

### General flow
```
<install packages>  
for _item in $TARGETS; do         
    if type do_${_item}_patch &>/dev/null; then
        do_${_item}_patch
    fi
done 
<install kselftests> 
for _item in $TARGETS; do
    if type do_${_item}_config &>/dev/null; then
        do_${_item}_config
    fi         
    <execute test(s)>
    if type do_${_item}_reset &>/dev/null; then
        do_${_item}_reset
    fi
done 
```
