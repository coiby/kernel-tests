#!/bin/bash
# This is for bug https://bugzilla.redhat.com/show_bug.cgi?id=1706088

which python && python=python || python=/usr/libexec/platform-python

function ppc64le_setup()
{
	rlIsRHEL ">=8" || return
	rlRun "git clone --depth 1 https://gitlab.com/redhat/centos-stream/tests/kernel/core/opos-tests tests"

	pushd tests
	rlRun "git checkout python3"
	rlRun "git pull --rebase origin python3"
	rlRun "yum -y install libvirt libvirt-devel"
	rlRun "sh ../../../../include/scripts/buildroot.sh python3-devel xz-devel numactl policycoreutils-python-utils python2 python2-devel"
	touch config/tests/host/memory_test.cfg
	cat > config/tests/host/memory_test.cfg <<EOF
avocado-misc-tests/memory/memhotplug.py
avocado-misc-tests/memory/fork_mem.py
avocado-misc-tests/memory/memory_api.py
avocado-misc-tests/memory/sum_check.py
avocado-misc-tests/memory/eatmemory.py
avocado-misc-tests/memory/mprotect.py
avocado-misc-tests/memory/ksm_poison.py avocado-misc-tests/memory/ksm_poison.py.data/ksm_poison.yaml
avocado-misc-tests/memory/child_spawn.py
avocado-misc-tests/memory/vatest.py avocado-misc-tests/memory/vatest.py.data/vatest.yaml
EOF
	rlRun "cat config/tests/host/memory_test.cfg"
	rlRun "$python avocado-setup.py"
	popd
}

function ppc64le_run()
{
	rlIsRHEL ">=8" || return
	pushd tests
	for i in $(seq 1 100); do
		rlLog "Looping: $i"
		rlRun "$python avocado-setup.py --run-suite host_memory_test"
	done
	popd
}
