#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 2089632 - "struct" command does not expand struct members within union
# Fixed in RHEL-9.1 crash-8.0.1-2.el9. It works in RHEL7/8
analyse() {
	if [ "$RELEASE" -ge 9 ]; then
		CheckSkipTest crash 8.0.1-2 && return
	fi

	# Check struct of a page
	local cmd="struct.cmd"
	local output="struct.out"

	cat <<EOF > "${cmd}"
struct page
exit
EOF

	crash -i ${cmd} > "${output}"
	ret=$?

	RhtsSubmit "$(pwd)/${cmd}"
	RhtsSubmit "$(pwd)/${output}"

	if [[ "$ret" -ne "0" ]];then
		Error "Failed to run crash command. Please check struct.out"
	fi

	# Expect structs within an union are expanded correctly

	# =====================
	# Output before the fix
	# =====================
	# struct page {
	#        [0x0] unsigned long flags;
	#              union {
	#                  struct {...};
	#                  struct {...};
	#                  struct {...};
	#                  struct {...};
	#                  struct {...};
	#                  struct {...};
	#                  struct {...};
	#        [0x8]     struct callback_head callback_head;
	#     . . . . . . . .

	# =====================
	# Output after the fix
	# =====================
	# [0] unsigned long flags;
	#        union {
	#            struct {
	#    [8]         struct list_head lru;
	#   [24]         struct address_space *mapping;
	#   [32]         unsigned long index;
	#   [40]         unsigned long private;
	#            };
	#            struct {
	#    [8]         unsigned long pp_magic;
	#   [16]         struct page_pool *pp;
	#   [24]         unsigned long _pp_mapping_pad;
	#   [32]         unsigned long dma_addr;
	#                union {
	#   [40]             unsigned long dma_addr_upper;
	#   [40]             atomic_long_t pp_frag_count;
	#                };
	#            };
	#     . . . . . . . .

	# Find the first union containing structs and return the line number of the first struct
	local start_ln=$(grep -A1 -n union "$output" | grep -m 1 struct | awk -F- '{print $1}')
	if [[ "$?" -ne "0" ]]; then
		Error "Failed. Struct command does not print any union items. Please check ${output} for details."
		return
	fi

	# get line number of the first occurence of keyword: "struct callback_head callback_head;"
	local end_ln=$(grep -m1 -n "struct callback_head callback_head" "${output}" | awk -F: '{print $1}')
	if [[ "$?" -ne "0" ]]; then
		Error "Failed. Struct command does not print struct callback_head. Please check ${output} for details."
		return
	fi

	# Try to find the unexpanded string.
	sed -n "${start_ln},${end_ln}p" "${output}" | grep -n "struct {...};"
	if [[ "$?" -eq "0" ]];then
		Error "Failed. Struct members are not expanded within an union. Please check ${output} for details."
	fi

}

#+---------------------------+
MultihostStage "$(basename "${0%.*}")" analyse
