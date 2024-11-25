#!/bin/bash

function rhel10_fatal_issues()
{
	true
}

function rhel10_unfix_issues()
{
	# setpgid01 failed on rhel10
	osver_in_range "1000" "1001" && tskip "setpgid01" unfix
	# RHEL-65410: ltp/lite move_pages04 test failed
	osver_in_range "1000" "1001" && tskip "move_pages04" unfix
	# set_mempolicy04 failed on rhel10
	osver_in_range "1000" "1001" && tskip "set_mempolicy04" unfix
	# logrotate_sh failed on rhel10
	osver_in_range "1000" "1001" && tskip "logrotate_sh" unfix
	# pty01 and ptem01 failed with kirk
	osver_in_range "1000" "1001" && tskip "pty01 ptem01" unfix
	# RHEL-65409: ltp/lite fanotify22 test failed
	osver_in_range "1000" "1001" && tskip "fanotify22" unfix
}

function rhel10_fixed_issues()
{
	true
}

function rhel10_knownissue_filter()
{
	rhel10_fatal_issues;
	rhel10_unfix_issues;
	rhel10_fixed_issues;
}
