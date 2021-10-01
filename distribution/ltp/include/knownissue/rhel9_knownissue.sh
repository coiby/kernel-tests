#!/bin/bash

function rhel9_fatal_issues()
{
	# systemd oom policy will send SIGTERM to restraintd
	osver_in_range "900" "901" && tskip "oom0.*" fatal
}

function rhel9_unfix_issues()
{
	# https://github.com/linux-test-project/ltp/issues/718
	is_arch "s390x" && tskip "ioctl09" unfix
	# https://bugzilla.redhat.com/show_bug.cgi?id=1913045#c24
	is_arch "aarch64" && tskip "ioctl_sg01" unfix
}

function rhel9_fixed_issues()
{
	return 0
}

function rhel9_knownissue_filter()
{
	rhel9_fatal_issues;
	rhel9_unfix_issues;
	rhel9_fixed_issues;
}
