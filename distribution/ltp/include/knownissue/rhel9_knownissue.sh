#!/bin/bash

function rhel9_unfix_issues()
{
	# https://github.com/linux-test-project/ltp/issues/718
	is_arch "s390x" && tskip "ioctl09" unfix
}

function rhel9_knownissue_filter()
{
	rhel9_unfix_issues;
}
