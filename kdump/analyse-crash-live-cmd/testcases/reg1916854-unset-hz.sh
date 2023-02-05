#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1916854 - crash: once scope is set,it can not be unset completely.
# Bug 1847538 - help -m showing incorrect hz value
# Fixed in RHEL-8.5 crash-7.3.0-2.el8.
analyse(){
    CheckSkipTest crash 7.3.0-2 && return
    local cmd="crash_scope.cmd"
    local output="crash_scope.out"

    # Before fixing BZ1916854, once scope is set, it can only set to
    # a different symbole but not able to unset it completely. e.g.
    # e.g.
    # crash> set scope
    # scope: 0 (not set)
    # crash> set scope schedule
    # scope: ffffffffbb1c12a0 (schedule)
    # crash> set scope 0
    # set: invalid text address: 0
    #
    # After the fix,
    # crash> set scope
    # scope: 0 (not set)
    # crash> set scope schedule
    # scope: ffffffffbb1c12a0 (schedule)
    # crash> set scope 0
    # scope: 0 (not set)   <= unset scope copmletely
    cat <<EOF >"$cmd"
help -m
set scope
set scope schedule
set scope
set scope 0
exit
EOF

    crash -i "$cmd" | tee "$output"

    RhtsSubmit "$(pwd)/$cmd"
    RhtsSubmit "$(pwd)/$output"

    ValidateCrashOutput "$output"

    #BZ1847538: Check hz value in output of 'help -m'
    local config_hz="$(cat /${K_BOOT}/config-$(uname -r) | awk -F"=" '/^CONFIG_HZ_[0-9]*=[yY]/ {split($1,ret,"_"); print ret[3]}')"
    if [ -z "$config_hz" ]; then
        Warn "Current kernel is not enabled with CONFIG_HZ_*. Please check /${K_BOOT}/config-$(uname -r).";
    elif ! grep -wq "hz: ${config_hz}" "$output"; then
        Error "'help -m' reported incorrect hz value. Expected value: ${config_hz}. Please check file '$output'"
    fi
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" analyse
