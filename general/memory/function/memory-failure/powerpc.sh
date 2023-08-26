#!/bin/bash
# This is for bug https://bugzilla.redhat.com/show_bug.cgi?id=1706088

function ppc64le_setup()
{
	rlIsRHEL ">=8" || return
	echo "cloning tests"
	git clone https://github.com/open-power-host-os/tests/

	cd tests
	git checkout python3
	git pull --rebase origin python3
	yum -y install libvirt libvirt-devel
	sh ../../../../include/scripts/buildroot.sh python3-devel xz-devel numactl policycoreutils-python-utils python2 python2-devel
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

	echo "config file:"
	cat config/tests/host/memory_test.cfg
	echo

	which python && python=python || python=/usr/libexec/platform-python
	$python avocado-setup.py
	ret=$?
	$python avocado-setup.py
	ret=$?
	cd -
	return $ret
}

function ppc64le_run()
{
	rlIsRHEL ">=8" || return
	cd tests
	which python &>/dev/null && python=python || python=/usr/libexec/platform-python
	[ "$python" = python ] || ln -s /usr/libexec/platform-python /usr/bin/python
	local i
	for i in $(seq 1 100); do
		echo "Looping: $i"
		$python avocado-setup.py --run-suite host_memory_test
	done
	cd -
}
