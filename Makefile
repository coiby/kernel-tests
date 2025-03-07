SHELL := /bin/bash

trailing_whitespace:
	whitespaces=$$((find . -type f -iname '*.sh' -exec grep -lPe '\s$$' {} + || true ) | sort) ; \
	if [[ -n "$${whitespaces}" ]]; then \
		echo "Files that have lines ending with whitespaces:" ; \
		echo "$${whitespaces}" | sed 's/^/  /' ; \
		echo "for more details run: grep -ne '\s$$' <filename>" ; \
		exit 1 ; \
	fi

mixed_tab_space:
	mixed=$$(comm -12 \
			<(find . -type f -iname '*.sh' -exec grep -lPe '^\t' {} + | sort) \
			<(find . -type f -iname '*.sh' -exec grep -lPe '^ ' {} + | sort)) ; \
	if [[ -n "$${mixed}" ]]; then \
		echo "Files with mixed tabs/spaces:" ; \
		echo "$${mixed}" | sed 's/^/  /' ; \
		echo "Use \"grep -nP '^\t' <filename>\" to list the lines starting with tab." ; \
		echo "Use \"grep -nP '^ ' <filename>\" to list the lines starting with space." ; \
		exit 1 ; \
	fi

internal_hostname:
	mirror="https://gitlab.com/redhat/centos-stream/src/kernel/documentation/-/raw/main/info/allowed-hosts.txt" ; \
	curl -L --retry 20 --remote-time -o .allowed-hosts "$${mirror}" ; \
	if [[ ! -f .allowed-hosts ]]; then \
		echo "Error: failed to fetch allowed-hosts from $${mirror}" ; \
		exit 1 ; \
	fi ; \
	readarray -t allowed_hosts < <(sed -e '/^#/d' -e 's/\s*#.*//' .allowed-hosts) ; \
	readarray -t internal_hosts < <(grep -hroE --exclude=.allowed-hosts '([a-zA-Z0-9\\.\\-]+\.redhat.com)' * | sort -u) ; \
	rm -f .allowed-hosts ; \
	fail=0 ; \
	for host in "$${internal_hosts[@]}"; do \
		allowed=0 ; \
		for allowed_host in "$${allowed_hosts[@]}"; do \
			if grep -E -w -q "$${allowed_host}" <<< "$${host}"; then \
				allowed=1 ; \
				break ; \
			fi \
		done ; \
		if [[ "$${allowed}" -eq 0 ]]; then \
			echo "FAIL: hostname $${host} is not allowed.  For details, refer to: $${mirror}" ; \
			fail=1 ; \
		fi \
	done ; \
	exit $${fail} ;

deprecated_uname:
	if grep --exclude-dir .git -Er "uname -[ip]"; then \
		echo "please use uname with '-m' parameter instead: https://bugzilla.redhat.com/show_bug.cgi?id=2126206" ; \
		exit 1 ; \
	fi

test :  trailing_whitespace mixed_tab_space internal_hostname deprecated_uname
