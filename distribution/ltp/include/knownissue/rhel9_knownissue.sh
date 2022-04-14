#!/bin/bash

function rhel9_fatal_issues()
{
	# systemd oom policy will send SIGTERM to restraintd
	osver_in_range "900" "901" && tskip "oom0.*" fatal
	# BZ2026959
	osver_in_range "900" "901" && is_arch "aarch64" && tskip "read_all_sys" fatal
}

function rhel9_unfix_issues()
{
	# https://bugzilla.redhat.com/show_bug.cgi?id=1913045#c24
	is_arch "aarch64" && tskip "ioctl_sg01" unfix
	# https://gitlab.com/cki-project/kernel-tests/-/issues/536#note_896846475
	tskip "ioctl09" unfix
	# remove this once using LTP > 20220121
	# https://gitlab.com/cki-project/kernel-tests/-/merge_requests/1187
	is_rt && osver_in_range "900" "901" && tskip "migrate_pages02" unfix
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
