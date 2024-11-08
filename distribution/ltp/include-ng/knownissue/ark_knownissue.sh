#!/bin/bash

function ark_knownissue_filter()
{
	# Test case issue in LTP/kernel upstream
	kernel_in_range "6.10.0" "6.13.0" && tskip "pty01 ptem01 pty06 setpgid01 set_mempolicy04" unfix
}
