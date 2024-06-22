#! /bin/bash -x
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   dep-install.sh of /kernel/filesystems/xfs/include
#   This file installs common dependencies
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if type -P yum >/dev/null; then
	YUM_PROG=$(type -P yum)
	YUM_OPTS="-y --skip-broken install"
fi
if [[ -e /run/ostree-booted ]]; then
	YUM_PROG="$(type -P rpm-ostree)"
	YUM_OPTS="--apply-live --idempotent --allow-inactive install"
fi
if type -P dnf >/dev/null && ! [[ -e /run/ostree-booted ]]; then
	YUM_PROG="$(type -P dnf)"
	YUM_OPTS="-y --best --allowerasing --setopt=strict=0"
fi
if type -P dnf5 >/dev/null && ! [[ -e /run/ostree-booted ]]; then
	YUM_PROG="$(type -P dnf5)"
	YUM_OPTS="-y --best --allowerasing --setopt=strict=0"
fi
$YUM_PROG $YUM_OPTS xfs-kmod xfsprogs xfsdump perl quota acl attr  bind-utils bc indent rpm-build autoconf libtool popt-devel libblkid-devel readline-devel gettext policycoreutils-python shadow-utils libuuid-devel e4fsprogs e2fsprogs e2fsprogs-devel gdbm-devel libaio-devel libattr-devel libacl-devel xfsprogs-devel btrfs-progs gfs2-utils gcc ncurses-devel pyOpenSSL git mdadm libcap git vim openssl-devel samba samba-client cifs-utils nfs-utils rpcbind lvm2 librbd1-devel librdmacm-devel vdo kmod-kvdo fio beakerlib libtirpc libtirpc-devel rpcgen blockdev userspace-rcu userspace-rcu-devel inih inih-devel
