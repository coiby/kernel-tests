#!/bin/bash

function ark_knownissue_filter()
{
	kernel_in_range "6.10.0" "6.16.0" && tskip "pty06 set_mempolicy04" unfix
}
