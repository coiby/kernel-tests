#!/bin/bash -
# shellcheck disable=SC2034
set -o nounset

# mandatory
if [  x"$SRIOV_TOPO"  == x"sriov_test_vmvf_connectivity_remain" ]
then
	echo "JOBID=$JOBID"
	echo "NIC_DRIVER=$NIC_DRIVER"
else
	echo "CLIENTS=$CLIENTS"
	echo "SERVERS=$SERVERS"
	echo "JOBID=$JOBID"
	echo "NIC_DRIVER=$NIC_DRIVER"
fi

set +o nounset

# optional
SRIOV_TOPO=${SRIOV_TOPO:-sriov_all}
SRIOV_SKIP_SETUP_ENV=${SRIOV_SKIP_SETUP_ENV:-no}
SRIOV_RUN_BY_PARTNER=${SRIOV_RUN_BY_PARTNER:-no}
SRIOV_ENABLE_SELINUX=${SRIOV_ENABLE_SELINUX:-yes}
# add to support rt-kernel
ENABLE_RT_KERNEL=${ENABLE_RT_KERNEL:-no}
# user need to defined vm cpu number
VM_CPUNUM=${VM_CPUNUM:-"3"}
# enable or disable beaker-NFV
ENABLE_DEFAULT_YUM=${ENABLE_DEFAULT_YUM:-yes}
# specify kernel version in vm
VM_KERNEL_NAME=${VM_KERNEL_NAME:-'None'}
# specify repo file to guest
GUEST_KERENL_REPO=${GUEST_KERENL_REPO:-'None'}
# specify brew task if to guest
BREW_TASK_ID=${BREW_TASK_ID:='None'}

# enable configure vm xml
ENABLE_VM_XML_TUNING=${ENABLE_VM_XML_TUNING:-'yes'}
#specify test nic if needed
CLIENT_INTERFACES=${CLIENT_INTERFACES:-'None'}
SERVER_INTERFACES=${SERVER_INTERFACES:-'None'}

# workaround for vf attaching to vm failing issue
SRIOV_USE_HOSTDEV=yes

rhel_version=$(cut -f1 -d. /etc/redhat-release | sed 's/[^0-9]//g')
KERNEL_VERSION=$(uname -r)
if (($rhel_version <= 6)); then
	image_name=${image_name:-"rhel6.9.qcow2"}
elif (($rhel_version == 7)); then
	image_name=${image_name:-"rhel7.7.qcow2"}
elif (($rhel_version == 8)); then
	image_name=${image_name:-"rhel8.6.qcow2"}
elif (($rhel_version == 9));then
	image_name=${image_name:-"rhel9.0.qcow2"}
elif (($rhel_version == 39));then
	image_name=${image_name:-"rhel9.2_cki.qcow2"}
fi

IMG_GUEST=${IMG_GUEST:-"http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/vm/${image_name}"}


kernel_ver="$(uname -r)"
if [ "$ENABLE_RT_KERNEL" = "no" ]; then
	if [ -z "$YUM_KERNEL" ]; then
		YUM_KERNEL="kernel-${kernel_ver}"
	fi
	if [ -z "$YUM_KERNEL_CORE" ]; then
		YUM_KERNEL_CORE="kernel-core-${kernel_ver}"
	fi
	if [ -z "$YUM_KERNEL_MODULES" ]; then
		YUM_KERNEL_MODULES="kernel-modules-${kernel_ver}"
	fi
	if [ -z "$YUM_KERNEL_MODULES_core" ]; then
		YUM_KERNEL_MODULES="kernel-modules-core-${kernel_ver}"
	fi
	if [ -z "$YUM_KERNEL_MODULES_INTERNAL" ]; then
		YUM_KERNEL_MODULES_INTERNAL="kernel-modules-internal-${kernel_ver}"
	fi
else
	if [ -z "$YUM_KERNEL" ]; then
		YUM_KERNEL="kernel-rt-${kernel_ver}"
	fi
	if [ -z "$YUM_KERNEL_CORE" ]; then
		YUM_KERNEL_CORE="kernel-core-rt-${kernel_ver}"
	fi
	if [ -z "$YUM_KERNEL_MODULES" ]; then
		YUM_KERNEL_MODULES="kernel-modules-rt-${kernel_ver}"
	fi
	if [ -z "$YUM_KERNEL_MODULES" ]; then
		YUM_KERNEL_MODULES="kernel-modules-core-rt-${kernel_ver}"
	fi
	if [ -z "$YUM_KERNEL_MODULES_INTERNAL" ]; then
		YUM_KERNEL_MODULES_INTERNAL="kernel-modules-internal-rt-${kernel_ver}"
	fi
fi

if [ "$ENABLE_RT_KERNEL" = "no" ]; then
	if [ -z "$RPM_KERNEL" ]; then
		RPM_KERNEL=$(uname -r | awk '{
			split($0,v,"-");
			s=v[2];
			do {
				i=index(s,".");
				s=substr(s, i+1)
			} while(i > 0)
			sub("."s,"",v[2]);
			print "http://download.devel.redhat.com/brewroot/packages/kernel/"v[1]"/"v[2]"/"s"/kernel-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
	if [ -z "$RPM_KERNEL_CORE" ]; then
		RPM_KERNEL_CORE=$(uname -r | awk '{
			split($0,v,"-");
			s=v[2];
			do {
				i=index(s,".");
				s=substr(s, i+1)
			} while(i > 0)
			sub("."s,"",v[2]);
			print "http://download.devel.redhat.com/brewroot/packages/kernel/"v[1]"/"v[2]"/"s"/kernel-core-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
	if [ -z "$RPM_KERNEL_MODULES" ]; then
		RPM_KERNEL_MODULES=$(uname -r | awk '{
			split($0,v,"-");
			s=v[2];
			do {
				i=index(s,".");
				s=substr(s, i+1)
			} while(i > 0)
			sub("."s,"",v[2]);
			print "http://download.devel.redhat.com/brewroot/packages/kernel/"v[1]"/"v[2]"/"s"/kernel-modules-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
	if [ -z "$RPM_KERNEL_MODULES_INTERNAL" ]; then
		RPM_KERNEL_MODULES_INTERNAL=$(uname -r | awk '{
			split($0,v,"-");
			s=v[2];
			do {
				i=index(s,".");
				s=substr(s, i+1)
			} while(i > 0)
			sub("."s,"",v[2]);
			print "http://download.devel.redhat.com/brewroot/packages/kernel/"v[1]"/"v[2]"/"s"/kernel-modules-internal-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
else
	if [ -z "$RPM_KERNEL" ]; then
		RPM_KERNEL=$(uname -r | awk '{
			split($0,v,"-");
			s=v[2];
			do {
				i=index(s,".");
				s=substr(s, i+1)
			} while(i > 0)
			sub("."s,"",v[2]);
			print "http://download.devel.redhat.com/brewroot/packages/kernel-rt/"v[1]"/"v[2]"/"s"/kernel-rt-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
	if [ -z "$RPM_KERNEL_CORE" ]; then
		RPM_KERNEL_CORE=$(uname -r | awk '{
			split($0,v,"-");
			s=v[2];
			do {
				i=index(s,".");
				s=substr(s, i+1)
			} while(i > 0)
			sub("."s,"",v[2]);
			print "http://download.devel.redhat.com/brewroot/packages/kernel-rt/"v[1]"/"v[2]"/"s"/kernel-core-rt-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
	if [ -z "$RPM_KERNEL_MODULES" ]; then
		RPM_KERNEL_MODULES=$(uname -r | awk '{
			split($0,v,"-");
			s=v[2];
			do {
				i=index(s,".");
				s=substr(s, i+1)
			} while(i > 0)
			sub("."s,"",v[2]);
			print "http://download.devel.redhat.com/brewroot/packages/kernel-rt/"v[1]"/"v[2]"/"s"/kernel-modules-rt-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
	if [ -z "$RPM_KERNEL_MODULES_CORE" ]; then
		RPM_KERNEL_MODULES=$(uname -r | awk '{
		  split($0,v,"-");
		  s=v[2];
		  do {
			  i=index(s,".");
			  s=substr(s, i+1)
		  } while(i > 0)
		  sub("."s,"",v[2]);
		  print "http://download.devel.redhat.com/brewroot/packages/kernel-rt/"v[1]"/"v[2]"/"s"/kernel-modules-core-rt-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
	if [ -z "$RPM_KERNEL_MODULES_INTERNAL" ]; then
		RPM_KERNEL_MODULES_INTERNAL=$(uname -r | awk '{
			split($0,v,"-");
			s=v[2];
			do {
				i=index(s,".");
				s=substr(s, i+1)
			} while(i > 0)
			sub("."s,"",v[2]);
			print "http://download.devel.redhat.com/brewroot/packages/kernel-rt/"v[1]"/"v[2]"/"s"/kernel-modules-internal-rt-"v[1]"-"v[2]"."s".rpm"
		}')
	fi
fi

#CLIENT AND SERVER HOST NIC names
if [ "$SERVERS" == "netqe35.knqe.eng.rdu2.dc.redhat.com" ]; then
	SERVER_INTERFACES=(ens802f0np0 ens802f1np1)
	CLIENT_INTERFACES=(ens801f0np0 ens801f1np1)
elif [ "$SERVERS" == "netqe36.knqe.eng.rdu2.dc.redhat.com" ]; then
	SERVER_INTERFACES=(ens801f0np0 ens801f1np1)
	CLIENT_INTERFACES=(ens802f0np0 ens802f1np1)
elif [ "$SERVERS" == "hpe-netqe-syn480g10-03.knqe.eng.rdu2.dc.redhat.com" ]; then
	SERVER_INTERFACES=(ens1f0 ens1f1)
	CLIENT_INTERFACES=(ens1f0 ens1f1)
elif [ "$SERVERS" == "hpe-netqe-syn480g10-04.knqe.eng.rdu2.dc.redhat.com" ]; then
	SERVER_INTERFACES=(ens1f0 ens1f1)
	CLIENT_INTERFACES=(ens1f0 ens1f1)
else
	SERVER_INTERFACES=()
	CLIENT_INTERFACES=()
fi

echo "rhel_version=$rhel_version"
echo "SRIOV_TOPO=$SRIOV_TOPO"
echo "SRIOV_SKIP_SETUP_ENV=$SRIOV_SKIP_SETUP_ENV"
echo "image_name=$image_name"
echo "IMG_GUEST=$IMG_GUEST"
echo "SRC_NETPERF=$SRC_NETPERF"
echo "RPM_KERNEL=$RPM_KERNEL"
echo "ENABLE_RT_KERNEL=${ENABLE_RT_KERNEL}"
echo "VM_CPUNUM=${VM_CPUNUM}"
echo "ENABLE_DEFAULT_YUM=${ENABLE_DEFAULT_YUM}"
echo "VM_KERNEL_NAME=${VM_KERNEL_NAME}"
echo "BREW_TASK_ID=${BREW_TASK_ID}"
echo "ENABLE_VM_XML_TUNING=${ENABLE_VM_XML_TUNING}"
echo "CLIENT_INTERFACES=${CLIENT_INTERFACES[*]}"
echo "SERVER_INTERFACES=${SERVER_INTERFACES[*]}"
echo "KERNEL_VERSION=\"${KERNEL_VERSION}\""
