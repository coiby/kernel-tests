#!/bin/sh
function brew_kpkg_install()
{
	if [ -f LAZY ]; then
		echo "LAZY mode."
		echo "Skip install kernel srpm and kernel-deubginfo kernel-devel."
		return 0;
	elif [[ "$INST" =~ NEVER ]]; then
		return 0
	fi

	karch=`uname -m`
	local kver=`uname -r | sed "s/\.$karch//"`
	local kvari=`echo $kver | grep -Eo '(debug|PAE|xen)$'`
	K_KVERS=`echo $kver | sed "s/[\.+]$kvari$//"`
	if curl --fail --head -s http://download.devel.redhat.com/rhel-5/brew/packages/kernel/${K_KVERS%-*}/${K_KVERS#*-}/$karch/kernel-`uname -r`.rpm -o /dev/null -f; then
		local url="http://download.devel.redhat.com/rhel-5/brew/packages/kernel"
	elif curl --fail --head -s http://download.devel.redhat.com/rhel-6/brew/packages/kernel/${K_KVERS%-*}/${K_KVERS#*-}/$karch/kernel-`uname -r`.rpm -o /dev/null -f; then
		local url="http://download.devel.redhat.com/rhel-6/brew/packages/kernel"
	else
		local url="http://download.devel.redhat.com/brewroot/packages/kernel"
	fi
	[[ $(rpm -qa kernel-rt) =~ $(uname -r)  ]] && url="${url}-rt" && kvari="rt"
	[[ $(rpm -qa kernel-pegas) =~ $(uname -r) ]] && url="${url}-pegas" && kvari="pegas"
	[ $? -ne 0 ] && [[ $(uname -r) =~ "4.14.*.aarch64" ]] && url="${url}-aarch64"
	pkg_kdevel="kernel-${kvari}-devel-${K_KVERS}.${karch}"
	pkg_kdevel=${pkg_kdevel/--/-}

	pkg_kheader="kernel-${kvari}-headers-${K_KVERS}.${karch}"
	pkg_kheader=${pkg_kheader/--/-}

	pkg_kdebuginfo_common="kernel-${kvari}-debuginfo-common-${karch}-${K_KVERS}.${karch}"
	pkg_kdebuginfo_common=${pkg_kdebuginfo_common/--/-}

	pkg_kdebuginfo="kernel-${kvari}-debuginfo-${K_KVERS}.${karch}"
	pkg_kdebuginfo=${pkg_kdebuginfo/--/-}

	pkg_ksrc=kernel-${kvari}-${K_KVERS}.src
	pkg_ksrc="${pkg_ksrc/--/-}"

	for p in $*; do
		echo "${!p}.rpm"
		if [[ $p =~ ksrc ]];then
			ls ${!p}.rpm
			if [[ $(uname -r) =~ "aarch64" ]]; then
				wget "${url}/${K_KVERS%-*}/${K_KVERS#*-}/src/kernel-aarch64-${K_KVERS}.src.rpm"
				rpm -q ${!p} || rpm -ivh --force kernel-aarch64-${K_KVERS}.src.rpm

			else
				wget "${url}/${K_KVERS%-*}/${K_KVERS#*-}/src/${pkg_ksrc}.rpm"
				rpm -q ${!p} || rpm -ivh --force ${pkg_ksrc}.rpm

			fi
			continue;
		elif [[ $p =~ kdebuginfo ]];then
				rpm -q ${!p} || {
				wget --quiet "${url}/${K_KVERS%-*}/${K_KVERS#*-}/${karch}/${pkg_kdebuginfo}.rpm"
				wget --quiet "${url}/${K_KVERS%-*}/${K_KVERS#*-}/${karch}/${pkg_kdebuginfo_common}.rpm"
				rpm -ivh --force ${pkg_kdebuginfo_common}.rpm ${pkg_kdebuginfo}.rpm
			}
		else
			rpm -q ${!p} || wget "${url}/${K_KVERS%-*}/${K_KVERS#*-}/${karch}/${!p}.rpm"
			! rpm -q ${!p} && [[ $p =~ "devel" ]] && rpm -Uvh --force ${pkg_kdevel}.rpm ||
				! rpm -q ${!p} && [[ $p =~ "headers" ]] && rpm -Uvh --force ${pkg_kheader}.rpm
		fi
done

if [ "$INST" = ONCE ]; then
	touch LAZY
fi
}
