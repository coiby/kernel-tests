#!/bin/sh
# This file is used for upstream specific test functions.
[ ! "$CKI_SELFTESTS_URL" ] && test_skip_exit "CKI_SELFTESTS_URL not find"

skip_tests=(
# CONFIG_TEST_BPF is not set
test_bpf.sh
# Skip bpf/test_progs and run the test individually
test_progs
)

# Tests in this list need large memory
large_mem_tests=(
tc-tests/filters/concurrency.json
tc-tests/filters/tests.json
)

# For upstream kselftest testing, we need a pre-build selftest tar ball url
install_upstream_iproute()
{
	dnf install -y git glibc-devel elfutils-devel elfutils-libelf-devel libmnl-devel libpcap
	git clone git://git.kernel.org/pub/scm/network/iproute2/iproute2.git
	pushd iproute2
	./configure && make && make install || \
		test_warn "upstream iproute2 install failed"
	popd
}

install_kselftests()
{
	# use upstream iproute2 for testing
	install_upstream_iproute
	mkdir selftests
	pushd selftests
	wget --no-check-certificate $CKI_SELFTESTS_URL -O kselftest.tar.gz
	tar zxf kselftest.tar.gz
	popd
	[ -f selftests/run_kselftest.sh ] && return 0 || return 1
}

install_netsniff()
{
	dnf install -y jq netsniff-ng
	which mausezahn && return 0 || return 1
}

install_smcroute()
{
	which smcroute && return 0
	yum install -y libcap-devel
	smc_v="2.4.4"
	wget https://github.com/troglobit/smcroute/releases/download/${smc_v}/smcroute-${smc_v}.tar.gz
	tar zxf smcroute-${smc_v}.tar.gz
	pushd smcroute-${smc_v}
	./autogen.sh && ./configure --sysconfdir=/etc --localstatedir=/var && make && make install
	popd
	which smcroute && return 0 || return 1
}

