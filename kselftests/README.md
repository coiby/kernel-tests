# kselftest test
This is a test wrapper for [kernel selftest](https://github.com/torvalds/linux/tree/master/tools/testing/selftests) to be run in beaker test environment.

You are also encouraged to read the [documentation](https://www.kernel.org/doc/html/latest/dev-tools/kselftest.html) on how to run these tests outside of the wrapper.

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

WAIVE_TARGETS 		List of selftests to waive. The same with SKIP_TARGETS. This list must be in test format "collection:test".
default none

INCLUDE			Include any files with special variables or function definitions. e.g. "net.sh"
default none

TEST_PARAMS 		List of test parameters. This parameter list must contain test name and test parameter the same time and separate with semicolon. With format like, e.g. "bpf:foo --test; bpf:bar --another --test".
default none

DEBUG_CMD		Run debug commands after running each test case. i.e. at the end of each check_result().
default none

WORKERS         Number of parallel execution processes of each test.
default 1

### Usage

The wrapper allows you to run your tests with four suites.
- One option is the pre-built package that comes with the kernel under test and is selected by setting variable DELIVERED_TESTS. This is restricted because not all selftests are built and so not delivered with selftests-internal.
- The second option is the pre-built upstream package and is selected by setting CKI_SELFTESTS_URL which needs to be the fully qualified path to the tar release. You will need to provide the collection(s) to be tested by setting TEST_ITEMS to that collection(s). At least one needs to be provided and if multiple collections, each collection must be separated by a space.
- The third option is the upstream source package and is selected by setting BUILD_FROM_SRC and UPSTREAM_SOURCE_URL which needs to be the fully qualified path to the tar release. You will need to provide the collection(s) to be tested by setting TEST_ITEMS to that collection(s). At least one needs to be provided and if multiple collections, each collection must be separated by a space.
- Final option is to build and install kselftests from the source of the kernel under test. This is selected by setting BUILD_FROM_SRC and not setting UPSTREAM_SOURCE_URL. You will need to provide the collection(s) to be tested by setting TEST_ITEMS to that collection(s). At least one needs to be provided and if multiple collections, each collection must be separated by a space.

Allowance for custom functions
- If you need to run special setup for your tests you will need to create a function with the name `do_<collection>_config` that should be defined in your include file.
- If you need to patch or cleanup after your specific collection, similar provisions have been made to accommodate using `do_<collection>_patch` and `do_<collection>_reset`.
- If you need to run the tests specially instead of the global running process, you can define your own running function like `do_<collection>_run`.
- Patch for all collections is applied before the harness is built. Setup and reset for each collection is executed before and after each collection is executed.

- TODO: At this time there is no direct support for individual tests being part of TEST_ITEMS. As a workaround you can create a custom function to run only those tests you want in a collection. Below are steps to follow in and a couple of examples.
    - create an include file or add your function to one of the existing include files in the `kselftests/include` folder.
    - The function name must include the name of the collection. So for net it would be do_net_run. But for net/forwarding you would change the `/` to `_` making the name do_net_forwarding_run.
    - You can now add the tests you want to run from that collection executing them with RunKSelfTest.\
    e.g.
    ```
    do_net_forwarding_run()
    {
        for test in \
            net/forwarding:mirror_gre_lag_lacp.sh \
            net/forwarding:mirror_gre_bridge_1q_lag.sh
        do
            RunKSelfTest ${test}
            ret=$?
            check_result 1 1 ${test} $ret
        done
    }
   ```   
    - The `1 1` in check_result represents the current test number and total number of tests run. You can add a count to make this accurate for reporting but in the example above this was for debugging so the count was ignored.
    - an example where count is added to correctly generate and show the current test and total.
    ```
    do_cgroup_run()
    {
        pushd ${EXEC_DIR}
        total=$(grep -c "^cgroup:" kselftest-list.txt)
        tests="$(grep  "^cgroup:" kselftest-list.txt)"
        for test in ${tests}
        do
            num=$(($num + 1))
            if [ "${test}" = "cgroup:test_cpuset_prs.sh" ]; then
                pushd cgroup || exit
                ./${test##cgroup:} -d 2
                popd || exit
            else
                RunKSelfTest ${test}
            fi
            ret=$?
            check_result ${num} ${total} ${test} $ret
        done
    }
    ```
    - You would then run selftests as normal, adding the collections in TEST_ITEMS that you want to test.
    - You will now also have to make sure to include the .sh that has the function you want to run, so `INCLUDE: <your>.sh`.
    - Adding multiple include files is also supported, but make sure if you do that there isn't another `do_<collection>_xxx` in that include file.

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

    if type do_${_item}_run &>/dev/null; then
        do_${_item}_run
    else
        <execute test(s)>
        <run debug cmds>
        <check results>
    fi

    if type do_${_item}_reset &>/dev/null; then
        do_${_item}_reset
    fi
done
```
### Examples

1. Delivered Tests

    **Beaker task for testing all the delivered test collections**:
```
    <task name="/kernel-tests/kselftests delivered tests" role="None">
        <fetch url="https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/archive/main/kernel-tests-main.tar.gz#kselftests"/>
            <params>
                <param name="DELIVERED_TESTS" value="y" />
            </params>
    </task>
```

Corresponding tmt entry:
```
environment:
    DELIVERED_TESTS: y
```

**Beaker task for testing select collections from the delivered tests**:
```
    <task name="/kernel-tests/kselftests select delivered tests" role="None">
        <fetch url="https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/archive/main/kernel-tests-main.tar.gz#kselftests"/>
            <params>
                <param name="DELIVERED_TESTS" value="y" />
                <param name="TEST_ITEMS" value="bpf net" />
                <param name="SKIP_TARGETS" value="bpf:test_lwt_ip_encap.sh net:netdevice.sh" />
                <param name="INCLUDE" value="net.sh" />
            </params>
    </task>
```

Corresponding tmt entry:
```
environment:
    DELIVERED_TESTS: y
    TEST_ITEMS: bp net
    SKIP_TARGETS: bpf:test_lwt_ip_encap.sh net:netdevice.sh
    INCLUDE: net.sh
```

2. Upstream Source

**Beaker task for upstream case** (Current issue when building aarch64 through beaker requires setting ARCH to arm64 to resolve.)
```
    <task name="/kernel-tests/kselftests upstream source" role="None">
        <fetch url="https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/archive/main/kernel-tests-main.tar.gz#kselftests"/>
            <params>
                <param name="ARCH" value="arm64" />
                <param name="TEST_ITEMS" value="bpf net" />
                <param name="BUILD_FROM_SRC" value="y" />
                <param name="UPSTREAM_SOURCE_URL" value="https://git.kernel.org/pub/scm/linux/kernel/git/shuah/linux-kselftest.git/snapshot/linux-kselftest-fixes-5.14-rc6.tar.gz" />
                <param name="INCLUDE" value="net.sh" />
            </params>
    </task>
```

Corresponding tmt entry: (ARCH variable can be removed if not running test through beaker)
```
environment:
    ARCH: arm64
    BUILD_FROM_SRC: y
    UPSTREAM_SOURCE_URL: https://git.kernel.org/pub/scm/linux/kernel/git/shuah/linux-kselftest.git/snapshot/linux-kselftest-fixes-5.14-rc6.tar.gz
    TEST_ITEMS: bpf net
    INCLUDE: net.sh
```

3. Downstream Source

**Beaker task to build using kernel source based on installed system** (same issue with aarch64 as above):
```
    <task name="/kernel-tests/kselftests kernel internal" role="None">
        <fetch url="https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/archive/main/kernel-tests-main.tar.gz#kselftests"/>
            <params>
                <param name="TEST_ITEMS" value="bpf net" />
                <param name="BUILD_FROM_SRC" value="y" />
                <param name="INCLUDE" value="net.sh" />
            </params>
    </task>
```

Corresponding tmt entry:
```
environment:
    BUILD_FROM_SRC: y
    TEST_ITEMS: bpf net
    INCLUDE: net.sh
```
****
