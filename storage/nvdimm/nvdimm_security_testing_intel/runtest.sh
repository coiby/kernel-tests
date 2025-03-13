#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# Include Storage related environment
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh || exit 200

dev=""
id=""
keypath="/etc/ndctl/keys"
masterkey="nvdimm-master"
masterpath="$keypath/$masterkey.blob"
backup_key=0
backup_handle=0
NFIT_BUS="ACPI.NFIT"
rc=1

do_skip()
{
	echo kernel $(uname -r): $1
	exit 77
}


check_prereq()
{
	if ! command -v "$1" >/dev/null; then
		do_skip "missing $1, skipping..."
	fi
}

err()
{
	echo test/$(basename $0): failed at line $1
	[ -n "$2" ] && "$2"
	exit $rc
}

if hostname | grep intel-purley-aep-02; then
	NMEM=nmem11
else
	tlog "Not runing on intel AEP NVDIMM server, exit"
	exit 0
fi

trap 'err $LINENO' ERR

setup ()
{
	tok ndctl disable-region -b "$NFIT_BUS" all
}

detect ()
{
	tok ndctl list -b "$NFIT_BUS" -D -d $NMEM -i
	dev=$NMEM
	[ -n "$dev" ] || err "$LINENO"
	id="$(ndctl list -b "$NFIT_BUS" -D -d $dev -i | grep "\"id\"" | awk -F\" '{print $4}')"
	[ -n "$id" ] || err "$LINENO"
}

setup_keys()
{
	if [ ! -d "$keypath" ]; then
		mkdir -p "$keypath"
	fi

	if [ -f "$masterpath" ]; then
		mv "$masterpath" "$masterpath.bak"
		backup_key=1
	fi
	if [ -f "$keypath/tpm.handle" ]; then
		mv "$keypath/tpm.handle" "$keypath/tmp.handle.bak"
		backup_handle=1
	fi

	tok "dd if=/dev/urandom bs=1 count=32 2>/dev/null | keyctl padd user ${masterkey} @u"
	tok "keyctl pipe $(keyctl search @u user ${masterkey}) > ${masterpath}"
}

test_cleanup()
{
	if keyctl search @u encrypted nvdimm:"$id"; then
		keyctl unlink "$(keyctl search @u encrypted nvdimm:"$id")"
	fi

	if keyctl search @u user "$masterkey"; then
		keyctl unlink "$(keyctl search @u user $masterkey)"
	fi

	if [ -f "$keypath"/nvdimm_"$id"_"$(hostname)".blob ]; then
		rm -f "$keypath"/nvdimm_"$id"_"$(hostname)".blob
	fi
}

post_cleanup()
{
	if [ -f $masterpath ]; then
		rm -f "$masterpath"
	fi
	if [ "$backup_key" -eq 1 ]; then
		mv "$masterpath.bak" "$masterpath"
	fi
	if [ "$backup_handle" -eq 1 ]; then
		mv "$keypath/tpm.handle.bak" "$keypath/tmp.handle"
	fi
}


#TODO: no lock_dimm sysfs node, how to lock?
#this function need to rewrite after test on intel nvdimm HW
lock_dimm()
{
	ndctl disable-dimm "$dev"
	# convert nmemX --> test_dimmY
	# For now this is the only user of such a conversion so we can leave it
	# inline. Once a subsequent user arrives we can refactor this to a
	# helper in test/common:
	#   get_test_dimm_path "nfit_test.0" "nmem3"
	handle="$(ndctl list -b "$NFIT_TEST_BUS0"  -d "$dev" -i | jq -r .[].dimms[0].handle)"
	test_dimm_path=""
	for test_dimm in /sys/devices/platform/"$NFIT_TEST_BUS0"/nfit_test_dimm/test_dimm*; do
		td_handle_file="$test_dimm/handle"
		test -e "$td_handle_file" || continue
		td_handle="$(cat "$td_handle_file")"
		if [[ "$td_handle" -eq "$handle" ]]; then
			test_dimm_path="$test_dimm"
			break
		fi
	done
	test -d "$test_dimm_path"

	# now lock the dimm
	echo 1 > "${test_dimm_path}/lock_dimm"
	sstate="$(get_security_state)"
	if [ "$sstate" != "locked" ]; then
		echo "Incorrect security state: $sstate expected: locked"
		err "$LINENO"
	fi
}

get_security_state()
{
	ndctl list -i -b "$NFIT_BUS" -d "$dev" | grep "security" | awk -F\" '{print $4}'
}

setup_passphrase()
{
	tok ndctl setup-passphrase "$dev" -k user:"$masterkey"
	sstate="$(get_security_state)"
	if [ "$sstate" != "unlocked" ]; then
		echo "Incorrect security state: $sstate expected: unlocked"
		err "$LINENO"
	fi
}

remove_passphrase()
{
	tok ndctl remove-passphrase "$dev"
	sstate="$(get_security_state)"
	if [ "$sstate" != "disabled" ]; then
		echo "Incorrect security state: $sstate expected: disabled"
		err "$LINENO"
	fi
}

erase_security()
{
	tok ndctl sanitize-dimm -c "$dev"
	sstate="$(get_security_state)"
	if [ "$sstate" != "disabled" ]; then
		echo "Incorrect security state: $sstate expected: disabled"
		err "$LINENO"
	fi
}

update_security()
{
	tok ndctl update-passphrase "$dev"
	sstate="$(get_security_state)"
	if [ "$sstate" != "unlocked" ]; then
		echo "Incorrect security state: $sstate expected: unlocked"
		err "$LINENO"
	fi
}

freeze_security()
{
	tok ndctl freeze-security "$dev"
}

test_1_security_setup_and_remove()
{
	setup_passphrase
	remove_passphrase
}

test_2_security_setup_and_update()
{
	setup_passphrase
	update_security
	remove_passphrase
}

test_3_security_setup_and_erase()
{
	setup_passphrase
	erase_security
}

#TODO this case need to be update
test_4_security_unlock()
{
	setup_passphrase
	lock_dimm
	ndctl enable-dimm "$dev"
	sstate="$(get_security_state)"
	if [ "$sstate" != "unlocked" ]; then
		echo "Incorrect security state: $sstate expected: unlocked"
		err "$LINENO"
	fi
	ndctl disable-region -b "$NFIT_TEST_BUS0" all
	remove_passphrase
}

#TODO this case need to be update
# This should always be the last nvdimm security test.
# with security frozen, nfit_test must be removed and is no longer usable
test_5_security_freeze()
{
	setup_passphrase
	freeze_security
	sstate="$(get_security_state)"
	if [ "$sstate" != "frozen" ]; then
		echo "Incorrect security state: $sstate expected: frozen"
		err "$LINENO"
	fi

	#TODO: On my test, bellow step doesn't work after freeze_security
	#From the man page, this need ndctl load-keys before module load
	ndctl remove-passphrase "$dev" && { echo "remove succeed after frozen"; }
	sstate="$(get_security_state)"
	echo "$sstate"
	if [ "$sstate" != "frozen" ]; then
		echo "Incorrect security state: $sstate expected: frozen"
		err "$LINENO"
	fi
}

test_6_load_keys()
{
	if keyctl search @u encrypted nvdimm:"$id"; then
		keyctl unlink "$(keyctl search @u encrypted nvdimm:"$id")"
	fi

	if keyctl search @u user "$masterkey"; then
		keyctl unlink "$(keyctl search @u user "$masterkey")"
	fi

	tok ndctl load-keys

	if keyctl search @u user "$masterkey"; then
		echo "master key loaded"
	else
		echo "master key failed to loaded"
		err "$LINENO"
	fi

	if keyctl search @u encrypted nvdimm:"$id"; then
		echo "dimm key loaded"
	else
		echo "dimm key failed to load"
		err "$LINENO"
	fi
}

tlog "running $0"
trun "uname -a"

setup
check_prereq "keyctl"
detect
test_cleanup
setup_keys
tlog "INFO: Test 1, security setup and remove"
test_1_security_setup_and_remove

tlog "INFO: Test 2, security setup, update, and remove"
test_2_security_setup_and_update

tlog "INFO: Test 3, security setup and erase"
test_3_security_setup_and_erase

#lock
#tlog "INFO: Test 4, unlock dimm"
#test_4_security_unlock

# Freeze should always be run last because it locks security state, no idea how
# to unlock it
#echo "Test 5, freeze security"
#test_5_security_freeze

# Load-keys is independent of actual nvdimm security and is part of key
# mangement testing.
#echo "Test 6, test load-keys"
#test_6_load_keys

test_cleanup
post_cleanup

report_result
tend
