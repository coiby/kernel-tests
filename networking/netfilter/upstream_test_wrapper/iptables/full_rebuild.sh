#! /usr/bin/bash

if [[ -e /etc/redhat-release ]]; then
	crb_repo=/etc/yum.repos.d/rhel-CRB-latest.repo
	[[ -f $crb_repo ]] && sed -i -e 's/\(enabled\)=0/\1=1/g' $crb_repo
	for pkg in autoconf git make gcc libtool; do
		rpm -q $pkg || dnf install -y $pkg
	done
fi

if [ ! -e ./libmnl/install/lib/pkgconfig/libmnl.pc ];then
	rm -rf libmnl
	git clone git://git.netfilter.org/libmnl || { echo "libmnl clone failed";exit 1; }
	pushd libmnl
	./autogen.sh
	./configure --enable-static --prefix="$PWD/install" || {
		echo "libmnl: configure failed"
		exit 1
	}
	make -j $(nproc) || { echo "libmnl: make failed"; exit 2; }
	make install || { echo "libmnl: make install failed"; exit 3; }
	popd
fi
export PKG_CONFIG_PATH="${PWD}/libmnl/install/lib/pkgconfig:${PKG_CONFIG_PATH}"


if [ ! -e ./libnftnl/install/lib/pkgconfig/libnftnl.pc ];then
	rm -rf libnftnl
	git clone git://git.netfilter.org/libnftnl || { echo "libnftnl clone failed"; exit 1; }
	pushd libnftnl
	./autogen.sh
	./configure --enable-static --prefix="$PWD/install" || {
		echo "libnftnl: configure failed"
		exit 1
	}
	make -j $(nproc) || { echo "libnftnl: make failed"; exit 2; }
	make install || { echo "libnftnl: make install failed"; exit 3; }
	popd
fi
export PKG_CONFIG_PATH="${PWD}/libnftnl/install/lib/pkgconfig:${PKG_CONFIG_PATH}"


if [ ! -x ./iptables/install/sbin/xtables-nft-multi ]; then
	rm -rf iptables
	git clone git://git.netfilter.org/iptables || { echo "iptables clone failed"; exit 1; }
	pushd iptables
	./autogen.sh
	#./configure  --prefix="$PWD/install"
	./configure --enable-static --enable-shared --prefix="$PWD/install"
	[[ $? -eq 0 ]] || { echo "iptables: configure failed"; exit 4; }
	make -j $(nproc) V=1 || { echo "iptables: make failed"; exit 5; }
	make install || { echo "iptables: make install failed"; exit 6; }
	popd
fi
ls -lh ./iptables/install/sbin/xtables-nft-multi
