#!/bin/bash

function ark_knownissue_filter()
{
	#  In test runner (kirk), runs tests with extra setsid() call:
	#  https://github.com/linux-test-project/kirk/issues/28
	kernel_in_range "6.10.0" "6.16.0" && tskip "pty01 ptem01 pty06 setpgid01 set_mempolicy04" unfix
}
