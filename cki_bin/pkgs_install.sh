#!/bin/bash
#
# Install packages according to metadata file
#
set -euo pipefail

function get_pkgs
{
    local metadata_file=${1?"*** metadata file ***"}
    local keyword="$2"
    local pkgs=""

    typeset _pkgs
    typeset kv=$(grep -E "^${keyword}=" "$metadata_file")
    if [[ -n "$kv" ]]; then
        # convert ';' to ',' as a new var $keyword will be created via eval
        kv="${kv//;/,}"
        # strip comment starting with '#'
        eval "$kv"

        # shellcheck disable=SC2086
        eval _pkgs=\$${keyword}
        pkgs+=" ${_pkgs//,/ }"
    fi

    echo "$pkgs"
}

function get_deps_pkgs
{
    local metadata_file="$1"
    get_pkgs "$metadata_file" "dependencies"
}

function get_soft_deps_pkgs
{
    local metadata_file="$1"
    get_pkgs "$metadata_file" "softDependencies"
}

function get_pkg_mgr
{
    [[ -x /usr/bin/dnf ]] && echo dnf || echo yum
}

function usage
{
    echo "Usage: $1 [-n] <metadata file>" >&2
    echo "e.g." >&2
    echo "       $1 -n metadata # dry run" >&2
    echo "       $1 metadata" >&2
}

dry_run="no"
while getopts ':nh' iopt; do
    case "$iopt" in
        n) dry_run="yes" ;;
        h) usage "$0"; exit 1 ;;
        :) echo "Option '-$OPTARG' wants an argument" >&2; exit 1 ;;
        '?') echo "Option '-$OPTARG' not supported" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

metadata_file=${1:-"metadata"}
if [[ ! -f "$metadata_file" ]]; then
    echo "File $metadata_file not found" >&2
    usage "$0"
    exit 1
fi

pkgs_deps=$(get_deps_pkgs "$metadata_file")
pkgs_soft_deps=$(get_soft_deps_pkgs "$metadata_file")
if [[ -z "$pkgs_deps" ]] && [[ -z "$pkgs_soft_deps" ]]; then
    echo "Packages to install not found" >&2
    exit 0
fi

pkg_mgr=$(get_pkg_mgr)
if [[ $dry_run == "yes" ]]; then
    echo "=== DRY RUN ==="
    if [[ -n "$pkgs_deps" ]]; then
        echo "$pkg_mgr -y install $pkgs_deps"
    fi
    if [[ -n "$pkgs_soft_deps" ]]; then
        echo "$pkg_mgr -y install --skip-broken $pkgs_soft_deps"
    fi
    exit 0
fi
if [[ -n "$pkgs_deps" ]]; then
    echo "Now install packages <$pkgs_deps >, please wait for a while ..."
    # shellcheck disable=SC2086
    $pkg_mgr -y install $pkgs_deps
fi
if [[ -n "$pkgs_soft_deps" ]]; then
    echo "Now try to install extra packages <$pkgs_soft_deps >, please wait for a while ..."
    # shellcheck disable=SC2086
    $pkg_mgr -y install --skip-broken $pkgs_soft_deps
fi
exit $?
