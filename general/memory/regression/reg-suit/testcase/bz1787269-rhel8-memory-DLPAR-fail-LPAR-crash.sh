
function bz1787269()
{
	local iter=10
	if ! test  "$(uname -m)" == ppc64le; then
		return
	fi
	rpm -q powerpc-utils || yum -y install powerpc-utils
	while ((iter)); do for op in r a r ; do drmgr -c mem -${op}; done; ((iter--)); done
	if lscpu | grep para; then
		for op in r a r ; do drmgr -c mem -${op}; done
	fi
}
