#!/bin/bash
#
# (fetch and) compile vanilla libmnl, libnftnl and nftables

LIBNFTNL_PATH=$(realpath ../libnftnl)
LIBMNL_PATH=$(realpath ../libmnl)
IPTABLES_PATH=$(realpath ../iptables)
FETCH_MISSING=false
CORES=$(grep -c '^processor' /proc/cpuinfo)
MAKE="make -j${CORES}"
CLI=readline
#CLI=editline
#CLI=linenoise

# get all the dependencies if needed
if [[ -e /etc/redhat-release ]]; then
	# for jansson-devel
	crb_repo=/etc/yum.repos.d/rhel-CRB-latest.repo
	[[ -f $crb_repo ]] && sed -i -e 's/\(enabled\)=0/\1=1/g' $crb_repo
	for pkg in iptables-devel readline-devel asciidoc gmp-devel jansson-devel libtool make gcc autoconf git bison flex bison-devel flex-devel; do
		rpm -q $pkg || dnf install -y $pkg
	done
	CLI=readline
	FETCH_MISSING=true
fi

cd "$(dirname $0)"

if [[ -f nftables/src/libnftables.c ]]; then
	cd nftables
	LIBNFTNL_PATH=$(realpath ../libnftnl)
	LIBMNL_PATH=$(realpath ../libmnl)
	IPTABLES_PATH=$(realpath ../iptables)
elif [[ ! -f src/libnftables.c ]]; then
	git clone git://git.netfilter.org/nftables
	cd nftables
	LIBNFTNL_PATH=$(realpath ../libnftnl)
	LIBMNL_PATH=$(realpath ../libmnl)
	IPTABLES_PATH=$(realpath ../iptables)
fi

if [[ ! -d $LIBMNL_PATH ]] && $FETCH_MISSING; then
	git clone git://git.netfilter.org/libmnl $LIBMNL_PATH
fi
if [[ -d $LIBMNL_PATH ]]; then
	# first libmnl build
	cd $LIBMNL_PATH
	rm -rf install
	make clean
	./autogen.sh
	./configure --enable-static --prefix="$PWD/install" || {
		echo "libmnl: configure failed"
		exit 1
	}
	$MAKE || { echo "libmnl: make failed"; exit 2; }
	make install || { echo "libmnl: make install failed"; exit 3; }
	cd -

	export PKG_CONFIG_PATH="${LIBMNL_PATH}/install/lib/pkgconfig:${PKG_CONFIG_PATH}"
fi

if [[ ! -d $LIBNFTNL_PATH ]] && $FETCH_MISSING; then
	git clone git://git.netfilter.org/libnftnl $LIBNFTNL_PATH
fi
if [[ -d $LIBNFTNL_PATH ]]; then
	cd $LIBNFTNL_PATH
	rm -rf install
	make clean
	./autogen.sh
	./configure --enable-static --prefix="$PWD/install" || {
		echo "libnftnl: configure failed"
		exit 1
	}
	$MAKE || { echo "libnftnl: make failed"; exit 2; }
	make install || { echo "libnftnl: make install failed"; exit 3; }
	cd -

	export PKG_CONFIG_PATH="${LIBNFTNL_PATH}/install/lib/pkgconfig:${PKG_CONFIG_PATH}"
fi

if [[ ! -d $LIBNFTNL_PATH ]] && $FETCH_MISSING; then
	git clone git://git.netfilter.org/libnftnl $LIBNFTNL_PATH
fi
if [[ -d $LIBNFTNL_PATH ]]; then
	cd $LIBNFTNL_PATH
	rm -rf install
	make clean
	./autogen.sh
	./configure --enable-static --prefix="$PWD/install" || {
		echo "libnftnl: configure failed"
		exit 1
	}
	$MAKE || { echo "libnftnl: make failed"; exit 2; }
	make install || { echo "libnftnl: make install failed"; exit 3; }
	cd -

	export PKG_CONFIG_PATH="${LIBNFTNL_PATH}/install/lib/pkgconfig:${PKG_CONFIG_PATH}"
fi

[[ -d $IPTABLES_PATH ]] && export PKG_CONFIG_PATH="${IPTABLES_PATH}/install/lib/pkgconfig:${PKG_CONFIG_PATH}"


# now build nftables
rm -rf install
make clean
./autogen.sh
./configure --enable-static --enable-shared --enable-man-doc --with-json --with-xtables \
	--with-cli=$CLI --prefix="$PWD/install" #\
#	CFLAGS="-fprofile-arcs -ftest-coverage"
[[ $? -eq 0 ]] || { echo "nftables: configure failed"; exit 4; }
$MAKE V=1 || { echo "nftables: make failed"; exit 5; }
make install || { echo "nftables: make install failed"; exit 6; }
