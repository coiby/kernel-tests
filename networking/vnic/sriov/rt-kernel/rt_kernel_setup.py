#! /usr/bin/python3
import subprocess
import uuid
import random
import xmltodict
import json
import os
import sys
import logging
import re

"""
input:
os_type: host or vm
vm_version: default support rhel7.6,rhel7.7,rhel7.8,rhel8.2,rhel8.3,rhel8.4,rhel8.5,rhel9.0
repo.json: inpit multiple customer repo url, the key is repo name, the value is repo url


shell_paramenter:
rhel_version: host rhel version
vm_name: inherit runtest.sh $vm
"""

logger = logging.getLogger(__name__)
logger.setLevel(level=logging.INFO)
handler = logging.FileHandler("/var/log/kernel-rt.log")
handler.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s %(pathname)s %(filename)s %(funcName)s %(lineno)s \
      %(levelname)s - %(message)s", "%Y-%m-%d %H:%M:%S")
handler.setFormatter(formatter)
logger.addHandler(handler)
my_env = os.environ.copy()


def runcmd(command):
    """
    :param command: input shell command
    :return: command result
    """
    ret = subprocess.Popen(command, shell=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           encoding="utf-8", env=my_env)
    try:
        stdout, stderr = ret.communicate(timeout=3600)
    except TimeoutError:
        ret.kill()
        stdout, stderr = ret.communicate()
        print(f"rt_kernel_setup.py: \nExecute command {command:s} timeout.")
        logger.info(f"rt_kernel_setup.py: \nExecute command {command:s} timeout.")
        print(f'rt_kernel_setup.py: \nStderr:{stderr}')
        logger.info(f'rt_kernel_setup.py: \nStderr:{stderr}')
        sys.exit(1)
    else:
        if ret.returncode != 0:
            print(f"rt_kernel_setup.py: \nExecute command {command:s} failed.")
            logger.info(f"rt_kernel_setup.py: \nExecute command {command:s} failed.")
            print(f"rt_kernel_setup.py: \nStderr:{stderr}")
            logger.info(f"rt_kernel_setup.py: \nStderr:{stderr}")
            return ret.returncode
        else:
            print(f"rt_kernel_setup.py: \nExecute command {command:s} successed.")
            logger.info(f"rt_kernel_setup.py: \nExecute command {command:s} successed.")
            print(f"rt_kernel_setup.py: \nStdout:{stdout}")
            logger.info(f"rt_kernel_setup.py: \nStdout:{stdout}")
            return stdout


def random_mac():
    """
    :return: a random mac address, use for define vm mac address
    """
    macaddr = [0x00, 0x16, 0x3e, random.randint(0x00, 0x7f), random.randint(0x00, 0xff), random.randint(0x00, 0xff)]
    return ':'.join(map(lambda x: "%02x" % x, macaddr))


def generate_uuid():
    """
    :return: a random uuid, use for define a vm uuid
    """
    uuid_value = uuid.uuid1()
    return uuid_value


def configure_host_repo(repo_dict, rhel_version):
    """
    use dict to reslov multiple repo, key == [name], value == repo
    :param rhel_version: use check_system_version to return a rhel version
    :param repo_dict: main function get a repo josn file, this json file use to choose right kernel and virt. --> json
    :return: return a host system version --> str
    """
    print(f"rt_kernel_setup.py: \nRuning configure_host_rpeo function, the system version is {rhel_version}.")
    logger.info(f"rt_kernel_setup.py: \nRuning configure_host_rpeo function, the system version is {rhel_version}.")
    if repo_dict.get(rhel_version):
        latest_advanced_virt = repo_dict.get(rhel_version).get('latest-ADVANCED-VIRT')
    else:
        print("rt_kernel_setup.py: \nRunning configure_host_repo function. "
              "Can't get repo, because can't decide which virt module need to use.")
        logger.info("rt_kernel_setup.py: \nRunning configure_host_repo function. "
                    "Can't get repo, because can't decide which virt module need to use.")
        sys.exit(1)
    runcmd('cat <<-EOF > /etc/yum.repos.d/latest-ADVANCED-VIRT.repo\n'
           '[latest-ADVANCED-VIRT]\n'
           'name=latest-ADVANCED-VIRT\n'
           'baseurl=%s\n'
           'enabled=1\n'
           'priority=1\n'
           'gpgcheck=0\n'
           'skip_if_unavailable=1\n'
           'EOF' % (latest_advanced_virt))
    print("rt_kernel_setup.py: \nConfigure host rt-kernel repo successed.")
    logger.info("rt_kernel_setup.py: \nConfigure host rt-kernel repo successed.")


def download_vm_image(vm_names, rhel_image_name=None):
    """
    :param rhel_image_name: decide which vm qcow2 image need to download
    :param vm_names: test vm name
    :return: if download successfully, return the image url
    """
    print(f"rt_kernel_setup.py: \nRuning download vm image function, vm name is {vm_names}.")
    image_disk_urls = []
    for vm_name in vm_names:
        # Configure two vm qcow2
        if os.path.exists(f'/var/lib/libvirt/images/{rhel_image_name}'):
            runcmd(f'cp --remove-destination /var/lib/libvirt/images/{rhel_image_name} '
                   f'/var/lib/libvirt/images/{vm_name}.qcow2')
            print(f'rt_kernel_setup.py: \nConfigure {vm_name}.qcow2 disk ready!')
        else:
            try:
                runcmd(
                    f'wget -nv -N http://netqe-infra01.knqe.lab.eng.bos.redhat.com/vm/{rhel_image_name} '
                    f'-P /var/lib/libvirt/images/')
            except Exception as a:
                print('rt_kernel_setup.py: \n', a)
                sys.exit(1)
            else:
                runcmd('echo "Download guest image from rt-kernel tuning script..."')
                runcmd(
                    f'cp --remove-destination /var/lib/libvirt/images/{rhel_image_name} '
                    f'/var/lib/libvirt/images/{vm_name}.qcow2')
                print(f'rt_kernel_setup.py: \nConfigure {vm_name}.qcow2 disk ready!')
        runcmd(f'virt-copy-in -a /var/lib/libvirt/images/{vm_name}.qcow2 /mnt/tests/kernel/networking/common/tools/brewkoji_install.sh /root')
        runcmd(f'LIBGUESTFS_BACKEND=direct virt-customize -a /var/lib/libvirt/images/{vm_name}.qcow2 --delete /etc/yum.repos.d/rhel*.repo')
        runcmd(
            f'LIBGUESTFS_BACKEND=direct virt-customize -a /var/lib/libvirt/images/{vm_name}.qcow2 --delete /etc/yum.repos.d/beaker*.repo')
        runcmd(
            f'LIBGUESTFS_BACKEND=direct virt-customize -a /var/lib/libvirt/images/{vm_name}.qcow2 --delete /etc/yum.repos.d/rcm-tools-rhel*.repo')
        image_disk_urls.append(f'/var/lib/libvirt/images/{vm_name}.qcow2')
    return image_disk_urls


def configure_vm_repo(vm_name, vm_rhel_version, my_repo=None):
    """
    Need to do: Configure multiple repo
    :param vm_name: vm name
    :param vm_rhel_version:Use vm_rhel_version version to decide which repo
    :param vm_name: which vm need to configure vm
    :param my_repo: define specify repo if you need
    :return: None
    """
    AppStream_url = None
    BaseOS_url = None
    CBR_url = None
    HighAvailability_url = None
    NFV_url = None
    RT_url = None
    ResilientStorage_url = None
    SAP_url = None
    BEAKER_HARNESS = None
    hostname = runcmd('/usr/bin/hostname')
    if 'pek' in hostname:
        if "8" <= vm_rhel_version < "9":
            AppStream_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/AppStream/x86_64/os/"
            BaseOS_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/BaseOS/x86_64/os/"
            CBR_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/CRB/x86_64/os/"
            HighAvailability_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/HighAvailability/x86_64/os/"
            NFV_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/NFV/x86_64/os/"
            RT_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/RT/x86_64/os/"
            ResilientStorage_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/ResilientStorage/x86_64/os/"
            SAP_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/SAP/x86_64/os/"
            SAPHANA_url = "http://download.eng.pek2.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/SAPHANA/x86_64/os/"
        elif vm_rhel_version >= "9":
            AppStream_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/AppStream/x86_64/os/"
            BaseOS_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/BaseOS/x86_64/os/"
            CBR_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/CRB/x86_64/os/"
            HighAvailability_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/HighAvailability/x86_64/os/"
            NFV_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/NFV/x86_64/os/"
            RT_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/RT/x86_64/os/"
            ResilientStorage_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/ResilientStorage/x86_64/os/"
            SAP_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/SAP/x86_64/os/"
            SAPHANA_url = "http://download.eng.pek2.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/SAPHANA/x86_64/os/"
    elif 'bos' in hostname:
        if "8" <= vm_rhel_version < "9":
            AppStream_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/AppStream/x86_64/os/"
            BaseOS_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/BaseOS/x86_64/os/"
            CBR_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/CRB/x86_64/os/"
            HighAvailability_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/HighAvailability/x86_64/os/"
            NFV_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/NFV/x86_64/os/"
            RT_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/RT/x86_64/os/"
            ResilientStorage_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/ResilientStorage/x86_64/os/"
            SAP_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/SAP/x86_64/os/"
            SAPHANA_url = "http://download-node-02.eng.bos.redhat.com/rhel-8/nightly/RHEL-8/latest-RHEL-8/compose/SAPHANA/x86_64/os/"
        elif vm_rhel_version >= "9":
            AppStream_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/AppStream/x86_64/os/"
            BaseOS_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/BaseOS/x86_64/os/"
            CBR_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/CRB/x86_64/os/"
            HighAvailability_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/HighAvailability/x86_64/os/"
            NFV_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/NFV/x86_64/os/"
            RT_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/RT/x86_64/os/"
            ResilientStorage_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/ResilientStorage/x86_64/os/"
            SAP_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/SAP/x86_64/os/"
            SAPHANA_url = "http://download-node-02.eng.bos.redhat.com/rhel-9/nightly/RHEL-9/latest-RHEL-9/compose/SAPHANA/x86_64/os/"
    else:
        print(f'rt_kernel_setup.py: \nconfigure_vm_repo can\'t find suit repo for test server')
        sys.exit(1)

    if AppStream_url is not None and BaseOS_url is not None and CBR_url is not None and \
            HighAvailability_url is not None and NFV_url is not None and RT_url is not None and \
            ResilientStorage_url is not None and SAP_url is not None and SAPHANA_url is not None and \
            BEAKER_HARNESS is not None:
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "rm -f /etc/yum.repos.d/*"')
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/AppStream.repo\n'
               '[AppStream]\n'
               'name=AppStream\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, AppStream_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/BaseOS.repo\n'
               '[BaseOS]\n'
               'name=AppStream\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, BaseOS_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/CBR.repo\n'
               '[CBR]\n'
               'name=CBR\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, CBR_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/HighAvailability.repo\n'
               '[HighAvailability]\n'
               'name=HighAvailability\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, HighAvailability_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/NFV.repo\n'
               '[NFV]\n'
               'name=NFV\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, NFV_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/RT.repo\n'
               '[RT]\n'
               'name=RT\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, RT_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/ResilientStorage.repo\n'
               '[ResilientStorage]\n'
               'name=ResilientStorage\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, ResilientStorage_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/SAP.repo\n'
               '[SAP]\n'
               'name=SAP\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, SAP_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/SAPHANA.repo\n'
               '[SAPHANA]\n'
               'name=SAPHANA\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, SAPHANA_url))
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/beaker-harness.repo\n'
               '[beaker-harness]\n'
               'name=beaker-harness\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'sslverify=0\n'
               'gpgcheck=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, BEAKER_HARNESS))
    if my_repo is not None:
        runcmd('/usr/local/bin/vmsh run_cmd %s "cat <<-EOF > /etc/yum.repos.d/my_repo.repo\n'
               '[my_repo]\n'
               'name=my_repo\n'
               'baseurl=%s\n'
               'enabled=1\n'
               'priority=1\n'
               'gpgcheck=0\n'
               'sslverify=0\n'
               'skip_if_unavailable=1\n'
               'EOF"' % (vm_name, my_repo))
    # runcmd(f'/usr/bin/sh /mnt/tests/kernel/networking/vnic/sriov/rt-kernel/scp_repo.sh {vm_name}')
    # add sslverify=0 to repo file. To reslove SSL certificate problem: self signed certificate in certificate chain
    runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum clean all"')
    runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum makecache"')
    print(f'rt_kernel_setup.py: \nConfigure {vm_name} repo successed.')


def install_vm_kernel_from_brew(vm_name, kernel_name=None, brew_task_id=None):
    """
    use brew command to install specify kernel.
    """
    runcmd(f"/usr/local/bin/vmsh run_cmd {vm_name} 'yum install -y java-headless'")
    runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "bash /root/brewkoji_install.sh"')
    if brew_task_id is not None:
        runcmd(
            f"/usr/local/bin/vmsh run_cmd {vm_name} 'mkdir /root/test-kernel && cd /root/test-kernel && brew download-task {brew_task_id} --arch x86_64 --arch noarch'")
    elif kernel_name is not None:
        runcmd(
            f"/usr/local/bin/vmsh run_cmd {vm_name} 'mkdir /root/test-kernel && cd /root/test-kernel && brew download-build {kernel_name} --arch x86_64 --arch noarch'")

    runcmd(f"/usr/local/bin/vmsh run_cmd {vm_name} 'yum localinstall -y --nogpgcheck /root/test-kernel/kernel*'")


def install_package_host(rhel_version):
    """
    don't use this function to install kernel, just install libvirt
    """
    runcmd("bash brewkoji_install.sh")
    runcmd('yum clean all')
    runcmd('yum makecache')
    print("rt_kernel_setup.py: \nStart install rt-tests and tuned")
    runcmd('yum install -y rt-tests')
    runcmd("yum install -y java-headless")
    runcmd('yum install -y tuned')
    runcmd('yum install -y tuned-profiles-realtime')
    runcmd('yum install -y tuned-profiles-nfv')
    try:
        if '8.4' <= rhel_version <= '8.6':
            # Becasue virt module name change to virt:av in rhel 8.4
            runcmd('yum module disable -y virt:rhel')
            runcmd('yum module enable -y virt:av/common')
            runcmd('yum module install -y virt:av/common')
        elif '8.0' <= rhel_version <= '8.3':
            runcmd('yum module disable -y virt:rhel')
            runcmd(f'yum module enable -y virt:{rhel_version}')
            runcmd(f'yum module install -y virt:{rhel_version}/common')
        elif '8.7' <= rhel_version < '9.0':
            runcmd('yum module enable -y virt:rhel')
            runcmd('yum module install -y virt:rhel/common')
        elif rhel_version >= '9.0':
            runcmd('yum -y install qemu-kvm')
            runcmd('yum -y install libvirt libvirt*')
        runcmd('yum install -y virt-install')
        runcmd('yum install -y libguestfs')
        runcmd('yum install -y libguestfs-tools')
        runcmd('yum install -y libvirt-admin')
        runcmd('yum install -y guestfs-tools')
        runcmd('yum install -y libguestfs-tools-c')
    except Exception as e:
        print("rt_kernel_setup.py:", e)
        print("rt_kernel_setup.py: \nInstall procress failed please check.")
        logger.error("rt_kernel_setup.py: \nInstall procress failed please check.")
        sys.exit(1)
    else:
        print("rt_kernel_setup.py: \nInstallnation rt-tests/tuned/libvirt successed.")
        logger.info("rt_kernel_setup.py: \nInstallnation rt-tests/tuned/libvirt successed.")


def install_package_vm(vm_name, **key_val):
    """
    :param vm_name: Specify the virtual machine name
    :param key_val: receive parameters as below
    :param enable_default_yum: if yes, vm will install kernel from beaker-NFV, if no, vm will install kernel from
    brew.
    :param vm_kernel_name: specify kernel package name
    :param brew_task_id: brew task id
    :param kernel_repo: temporary repo path
    :return: None
    """
    print(f"rt_kernel_setup.py install_package_vm function: \nStart install rt-kernel in {vm_name}. ")

    if key_val.get('enable_default_yum') == 'yes':
        print(f"rt_kernel_setup.py install_package_vm function: \nwill install kernel-rt by default yum repo")
        try:
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y  kernel-rt"')
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y kernel-rt-core"')
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y kernel-rt-modules"')
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y kernel-rt-devel"')
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y kernel-rt-modules-internal"')
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y kernel-rt-modules-extra"')
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y rt-tests"')

        except Exception as e:
            print("rt_kernel_setup.py:", e)
            print("rt_kernel_setup.py: \nInstall progress failed please check.")
            sys.exit(1)
        else:
            print(f"rt_kernel_setup.py: \nInstallation rt-kernel in {vm_name} vm succeed.")
    elif key_val.get('enable_default_yum') is None or key_val.get('enable_default_yum') == 'no':
        if key_val.get('kernel_repo') is not None and key_val.get('vm_kernel_name') is not None:
            print(f"rt_kernel_setup.py: \nStart install rt-kernel from specify repo in {vm_name}."
                  f"the specify repo is: {key_val.get('kernel_repo')}\n"
                  f"the specify kernel name is: {key_val.get('vm_kernel_name')}")
            try:
                # runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y rt-tests"')
                # install kernel from specify repo
                runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y --enablerepo=my_repo kernel-rt"')
                runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y --enablerepo=my_repo kernel-rt-core"')
                runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y --enablerepo=my_repo kernel-rt-modules"')
                runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y --enablerepo=my_repo kernel-rt-devel"')
                runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y --enablerepo=my_repo kernel-rt-modules-internal"')
                runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y --enablerepo=my_repo kernel-rt-modules-extra"')
                runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y rt-tests"')
            except Exception as e:
                print("rt_kernel_setup.py:", e)
                print("rt_kernel_setup.py: \nInstall procress failed please check.")
                sys.exit(1)
            else:
                print(f"rt_kernel_setup.py: \nInstallnation rt-kernel in {vm_name} vm succeed.")
        elif key_val.get('brew_task_id') is not None or key_val.get('vm_kernel_name') is not None:
            # install kernel from specify task id or brew package name.
            print(f"rt_kernel_setup.py: \nStart install rt-kernel from brew in {vm_name}.")
            try:
                install_vm_kernel_from_brew(vm_name, key_val.get('vm_kernel_name'), key_val.get('brew_task_id'))
            except Exception as e:
                print("rt_kernel_setup.py:", e)
                print("rt_kernel_setup.py: \nInstall procress failed please check.")
            else:
                print(f"rt_kernel_setup.py: \nInstallnation rt-kernel in {vm_name} vm succeed.")
    runcmd(
        f'/usr/local/bin/vmsh run_cmd {vm_name} \
                                    "yum install -y tuned"')
    runcmd(
        f'/usr/local/bin/vmsh run_cmd {vm_name} \
                                                "yum install -y tuned-profiles-realtime"')
    runcmd(
        f'/usr/local/bin/vmsh run_cmd {vm_name} \
                                                "yum install -y tuned-profiles-nfv"')
    runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "yum install -y kernel-kernel-networking-common"')
    # install script from beaker task repo.
    runcmd(f"""
            /usr/local/bin/vmsh run_cmd {vm_name} "yum install -y kernel-kernel-networking-vnic-sriov.noarch"
            """)
    print(f"rt_kernel_setup.py install_package_vm function: \ninstall package finished ")
    logger.info("rt_kernel_setup.py install_package_vm function: \ninstall package finished")


def configure_huge_page(os_type, vm_name=None):
    """
    for host set 20 huge pages and huge page size == 1G
    for vm set 1 huge page and huge page size == 1G
    :param os_type: check host or vm
    :param vm_name: if os_type is vm, need vm name to run command
    :return: None
    """
    if os_type == 'host':
        runcmd(
            '/usr/sbin/grubby --args="default_hugepagesz=1G hugepagesz=1G hugepages=24" --update-kernel=$(/usr/sbin/grubby --default-kernel)')
        runcmd('echo "vm.nr_hugepages = 24" >> /etc/sysctl.conf')
    elif os_type == 'vm':
        runcmd(f"""
        /usr/local/bin/vmsh run_cmd {vm_name} "grubby --args='default_hugepagesz=1G hugepagesz=1G hugepages=1' --update-kernel=\$(grubby --default-kernel)"
            """)
        runcmd(f"""/usr/local/bin/vmsh run_cmd {vm_name} "echo 'vm.nr_hugepages = 1' >> /etc/sysctl.conf"
            """)
        print("rt_kernel_setup.py: \nConfigure_huge_page the grubby --default-kernel.")
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')


def get_cores():
    """
    :return: all cores except core0
    """
    sockets = []
    cores = []
    core_map = {}

    fd = open("/proc/cpuinfo")
    lines = fd.readlines()
    fd.close()

    core_details = []
    core_lines = {}
    for line in lines:
        # Delete space line
        if len(line.strip()) != 0:
            name, value = line.split(":", 1)
            # get all information from /proc/cpuinfo and set a key/value
            core_lines[name.strip()] = value.strip()
        else:
            core_details.append(core_lines)
            core_lines = {}

    for core in core_details:
        # physical id == socket, core id == core, processor == processor
        for field in ["processor", "core id", "physical id"]:
            if field not in core:
                print("Error getting '%s' value from /proc/cpuinfo" % field)
                sys.exit(1)
            core[field] = int(core[field])
        if core["core id"] not in cores:
            cores.append(core["core id"])
        if core["physical id"] not in sockets:
            sockets.append(core["physical id"])
        key = (core["physical id"], core["core id"])
        if key not in core_map:
            core_map[key] = []
        # (Socket num, core num): [processor1, processor2]
        core_map[key].append(core["processor"])
    """
        isolate all of cpu which core_id=0
        if disable HT scenario, all of cpus which the frist cpu of numa node won't isolated
        if enable HT scenario, all of sibling cores which the firest cpu of numa node won't isolated
    """
    # find the smallest core on each numa
    smallest_core_list = []
    for numa in sockets:
        search_core_list = []  # find the smallest core id
        for key, val in core_map.items():
            if numa == key[0]:
                search_core_list.append(int(key[1]))
        search_core_list.sort(reverse=False)
        smallest_core = search_core_list[0]
        smallest_core_list.append(smallest_core)
    smallest_core_list = list(set(smallest_core_list))
    smallest_cpu_list = {key: val for key, val in core_map.items() if int(key[1]) in smallest_core_list}
    core_map = {key: val for key, val in core_map.items() if int(key[1]) not in smallest_core_list}
    return core_map,smallest_cpu_list


def get_isolate_cpus_list():
    """
    :return: a list type cores ranges expect cpus of core0
    """
    isolate_cpu_dict, _ = get_cores()
    isolate_cpu_list = []
    # aviod enable HT and more than 2 numa node situation.
    for val in isolate_cpu_dict.values():
        for tmp in val:
            isolate_cpu_list.append(tmp)
    isolate_cpu_list.sort()
    return isolate_cpu_list


def get_isolate_cpus_str():
    """
    :return: a str type core like 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
    """
    isolate_cpus_list = get_isolate_cpus_list()
    # change int to str type of data and add "," into str.
    isolate_cpus_str = ",".join(list(map(lambda x: str(x), isolate_cpus_list)))
    print(isolate_cpus_str)
    return isolate_cpus_str


def get_cpu_from_specify_numa_node(numanode):
    isolate_cpu_dict, _ = get_cores()
    isolate_cpu_list = []
    isolate_cpu_dict = {key: val for key, val in isolate_cpu_dict.items() if 0 != key[1] and int(numanode) == key[0]}
    for val in isolate_cpu_dict.values():
        for tmp in val:
            isolate_cpu_list.append(tmp)
    isolate_cpu_list.sort()
    return isolate_cpu_list

def get_housekeeping_cpus_from_specify_numa_node(numanode):
    _, housekeeping_cpu_dict = get_cores()
    housekeeping_cpu_list = []
    housekeeping_cpu_dict = {key: val for key, val in housekeeping_cpu_dict.items() if key[0] == int(numanode)}
    for val in housekeeping_cpu_dict.values():
        for tmp in val:
            housekeeping_cpu_list.append(tmp)
    housekeeping_cpu_list.sort()
    housekeeping_cpu_str = ",".join(list(map(lambda x: str(x), housekeeping_cpu_list)))
    return housekeeping_cpu_str

# def find_host_cpu():
#     check_string = runcmd('lscpu -J')
#     check_cpu_number = eval(check_string)
#     lscpu_list = check_cpu_number['lscpu']
#     cpunum = None
#     # get cpu numbers
#     for i in lscpu_list:
#         # when the system in CH_CN, it will show CPU, in eng env, it will show CPU(s)
#         if i.get('field') == 'CPU:' or i.get('field') == 'CPU(s):':
#             cpunum = int(i.get('data')) - 1
#         else:
#             pass
#     return cpunum


def configure_cpu_isolate(os_type, rhel_version=None, vm_name=None, vcpu=None):
    # get vm/host cpu infomation
    if os_type == 'host':
        # keep core0 two siblings for housekeeping, if host enable HT
        isolated_cores = get_isolate_cpus_str()
        runcmd(f'echo isolated_cores={isolated_cores} > /etc/tuned/realtime-virtual-host-variables.conf')
        runcmd(f'echo isolate_managed_irq=Y >> /etc/tuned/realtime-virtual-host-variables.conf')
        if rhel_version == '8.2':
            runcmd('/usr/sbin/grubby --args="mitigations=off" --update-kernel=`/usr/sbin/grubby --default-kernel`')
        elif '8' > rhel_version >= '7':
            runcmd('/usr/sbin/grubby --args="spectre_v2=off nopti" --update-kernel=`/usr/sbin/grubby --default-kernel`')
            runcmd('/usr/sbin/grubby --args="kvm-intel.vmentry_l1d_flush=never" '
                   '--update-kernel=`/usr/sbin/grubby --default-kernel`')
        runcmd('/usr/sbin/tuned-adm profile realtime-virtual-host')
        # RT Host Setup --- Extra Setup for Better Performance
        runcmd('systemctl stop irqbalance.service')
        runcmd('/usr/sbin/chkconfig irqbalance off')
        runcmd('/usr/sbin/swapoff -a')
    elif os_type == 'vm':
        if vcpu is None:
            check_vm_information = runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "lscpu -e=cpu"')
            total_logical_cpu_num = \
                re.split(r'\[\w+\@\w+\s~\]#\s(lscpu -e=cpu\s+|echo \$\?\s+)', check_vm_information)[2].split()[-1]
            #strip('\x1b[?2004l\n').strip('\x1b[?2004h')
        else:
            total_logical_cpu_num=int(vcpu) - 1
        print(f"rt_kernel_setup.py: \nFind the cpu number, the cpu number is 0-{total_logical_cpu_num}.")
        isolated_cores = f'1-{total_logical_cpu_num}'
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "echo isolated_cores={isolated_cores} > /etc/tuned/realtime'
               f'-virtual-guest-variables.conf"')
        runcmd(
            f'/usr/local/bin/vmsh run_cmd {vm_name} "echo isolate_managed_irq=Y'
            f'>> /etc/tuned/realtime-virtual-guest-variables.conf"')
        # For RHEL8.2 only,Add boolean option "isolate_managed_irq=Y" to /etc/tuned/realtime-virtual-host-variables.conf
        if rhel_version == '8.2':
            runcmd(f"""/usr/local/bin/vmsh run_cmd {vm_name} "grubby --args='mitigations=off' \
--update-kernel=\$(grubby --default-kernel)"
                """)
            print("rt_kernel_setup.py: \nConfigure_host_cpu_isolate grubby --args=mitigations=off.")
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
        elif '8' > rhel_version >= '7':
            runcmd(f"""/usr/local/bin/vmsh run_cmd {vm_name} "grubby --args='spectre_v2=off nopti' \
--update-kernel=\$(grubby --default-kernel)"
                """)
            print("rt_kernel_setup.py: \nConfigure_host_cpu_isolate grubby --args=spectre_v2=off nopti.")
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
            runcmd(f"""/usr/local/bin/vmsh run_cmd {vm_name} "grubby --args='kvm-intel.vmentry_l1d_flush=never' \
--update-kernel=\$(grubby --default-kernel)"
            """)
            print("rt_kernel_setup.py: \nConfigure_host_cpu_isolate grubby --args=kvm-intel.vmentry_l1d_flush=never.")
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "tuned-adm profile realtime-virtual-guest"')
        # RT Host Setup --- Extra Setup for Better Performance
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "systemctl stop irqbalance.service"')
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "chkconfig irqbalance off"')
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "swapoff -a"')
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
    else:
        print("rt_kernel_setup.py: \nWrong os_type parameter was specified, script will exit.")
        sys.exit(1)


def define_vm_xml(vm_image_url, vm_names, **key_args):
    """
    :param vm_image_url: use download_vm_image() to download a qcow2, and rename vm name store in
    /var/lib/libvirt/image/{vm_name}
    :param vm_name: a list of guests
    :param key_args: receive below parameters
    vm_names, mac4vm1, mac4vm1if2, mac4vm2, vm_image_url, numa_node, vm_cpunum,vm_rhel_version, enable_vm_xml_tuning
    :param vm_names:receive two vm name as parameters: --> list, default is v[vm1,vm2]
    :param numa_node: which cores of numa node need to be used
    :param vm_rhel_version: defind which xml use to create vm
    :param mac4vm1: vm1 network interface1
    :param mac4vm1if2:vm1 network interface2
    :param mac4vm2:vm2 network interface1
    :param vm_cpunum: defined vm cpu numbers: object ---> int
    :param enable_vm_xml_tuning: enable xml tunning or not.
    :return:None
    """
    if vm_names is None or vm_image_url is None:
        print(f"rt_kernel_setup.py: \n define_vm_xml can't got vm name/ vm_image_url")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml can't got vm name. please check it. "
                    f"{vm_names}")
        sys.exit(1)
    else:
        print(f"rt_kernel_setup.py: \n define_vm_xml got vm name {vm_names}, vm_image_url {vm_image_url}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got vm name {vm_names}, vm_image_url {vm_image_url}")
    if key_args.get('numa_node') is not None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml got numa_node {key_args.get('numa_node')}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got kernel_repo {key_args.get('test_nic')}")
    if key_args.get('vm_rhel_version') is not None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml got vm_rhel_version {key_args.get('vm_rhel_version')}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got vm_rhel_version {key_args.get('vm_rhel_version')}")
    if key_args.get('mac4vm1') is not None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml got mac4vm1 {key_args.get('mac4vm1')}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got mac4vm1 {key_args.get('mac4vm1')}")
    if key_args.get('mac4vm1if2') is not None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml mac4vm1if2 {key_args.get('mac4vm1if2')}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got mac4vm1if2 {key_args.get('mac4vm1if2')}")
    if key_args.get('mac4vm2') is not None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml got mac4vm2 {key_args.get('mac4vm2')}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got mac4vm2 {key_args.get('mac4vm2')}")
    if key_args.get('vm_cpunum') is not None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml got vm_cpunum {key_args.get('vm_cpunum')}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got vm_cpunum {key_args.get('vm_cpunum')}")
    if key_args.get('numa_node') is not None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml got numa_node {key_args.get('numa_node')}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got numa_node {key_args.get('numa_node')}")
        got_isolation_cpu_on_numa_node_list = get_cpu_from_specify_numa_node(key_args.get('numa_node'))
        got_housekeeping_cpu_on_numa_node = get_housekeeping_cpus_from_specify_numa_node(key_args.get('numa_node'))
        print(
            f"rt_kernel_setup.py: \ngot isolated cpu {got_isolation_cpu_on_numa_node_list} on "
            f"{key_args.get('numa_node')}")
    if key_args.get('enable_vm_xml_tuning') is not None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml got enable_vm_xml_tuning {key_args.get('enable_vm_xml_tuning')}")
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got enable_vm_xml_tuning "
                    f"{key_args.get('enable_vm_xml_tuning')}")
    if key_args.get("vm_rhel_version") is not None:
        print(f'rt_kernel_setup.py: \nvm kernel version is {key_args.get("vm_rhel_version")}')
        logger.info(f"rt_kernel_setup.py: \ndefine_vm_xml got vm_rhel_version {key_args.get('vm_rhel_version')}")
    support_vm_xml_version = ['7', '8', '9']


    if key_args.get("enable_vm_xml_tuning") == 'yes' and key_args.get('numa_node') is None:
        print(f"rt_kernel_setup.py: \ndefine_vm_xml:enable xml tunning but can't got numa node")
        logger.info(f"rt_kernel_setup.py: \nefine_vm_xml:enable xml tunning but can't got numa node")
        sys.exit(1)

    if key_args.get("enable_vm_xml_tuning") == 'yes' and key_args.get("vm_rhel_version") in support_vm_xml_version \
            and (len(vm_names) * int(key_args.get('vm_cpunum'))) <= len(got_isolation_cpu_on_numa_node_list):
        print(f"rt_kernel_setup.py: \nenable xml tunning, vcpu num is {key_args.get('vm_cpunum')}.")
        for vm_name in vm_names:
            if vm_name == vm_names[0]:
                with open(
                        f'/mnt/tests/kernel/networking/vnic/sriov/rt-kernel/rhel{key_args.get("vm_rhel_version")}.xml',
                        'r') as e:
                    data = e.read()
                vm_data = json.loads(json.dumps(xmltodict.parse(data, process_namespaces=True)))
                vm_data['domain']['name'] = f'{vm_name}'  # define vm name
                vm_data['domain']['uuid'] = generate_uuid()  # define a random uuid
                vm_data['domain']['vcpu']['#text'] = f"{key_args.get('vm_cpunum')}"  # define a vcpu number
                # define memory same sa node
                vm_data['domain']['numatune']['memory']['@nodeset'] = f"{key_args.get('numa_node')}"
                # define memory same sa node
                vm_data['domain']['numatune']['memnode']['@nodeset'] = f"{key_args.get('numa_node')}"
                # define vcpupin
                vcpu_pins = []
                for i in range(0, int(key_args.get('vm_cpunum'))):
                    vcpu_pin = {'@vcpu': f'{i}', '@cpuset': f'{got_isolation_cpu_on_numa_node_list.pop(0)}'}
                    vcpu_pins.append(vcpu_pin)
                vm_data['domain']['cputune']['vcpupin'] = vcpu_pins
                vm_data['domain']['cputune'].update(
                    {'emulatorpin': {'@cpuset': got_housekeeping_cpu_on_numa_node},
                     })
                # define a vcpu  schedule priority
                vcpuscheds = []
                # remind vcpu 0 role as housekeeping
                for i in range(1, int(key_args.get('vm_cpunum'))):
                    vcpusched = {'@vcpus': f'{i}', '@scheduler': 'fifo', '@priority': '1'}
                    vcpuscheds.append(vcpusched)
                vm_data['domain']['cputune'].update({'vcpusched': vcpuscheds})
                vm_data['domain']['cpu']['numa']['cell']['@cpus'] = f"0-{int(key_args.get('vm_cpunum')) - 1}"
                # modify disk file
                vm_data['domain']['devices']['disk']['source']['@file'] = f"{vm_image_url[0]}"
                # modify network device
                interface_list = []
                interface1 = {'@type': 'bridge', 'mac': {'@address': f"{key_args.get('mac4vm1')}"},
                              'source': {'@bridge': 'virbr0'}, 'target': {'@dev': 'vnet0'},
                              'model': {'@type': 'virtio'}, 'alias': {'@name': 'net0'},
                              'address': {'@type': 'pci', '@domain': '0x0000', '@bus': '0x03',
                                          '@slot': '0x00', '@function': '0x0'}}
                # add network device
                interface2 = {'@type': 'bridge', 'mac': {'@address': f"{key_args.get('mac4vm1if2')}"},
                              'source': {'@bridge': 'virbr1'}, 'target': {'@dev': 'vnet1'},
                              'model': {'@type': 'virtio'}, 'alias': {'@name': 'net1'},
                              'address': {'@type': 'pci', '@domain': '0x0000', '@bus': '0x05',
                                          '@slot': '0x00', '@function': '0x0'}}
                interface_list.append(interface1)
                interface_list.append(interface2)
                vm_data['domain']['devices']['interface'] = interface_list
                with open(f'/mnt/tests/kernel/networking/vnic/sriov/rt-kernel/{vm_name}.xml', 'w') as a:
                    a.write(xmltodict.unparse(vm_data, pretty=True))
                # start guest
                runcmd(f"virsh define --file /mnt/tests/kernel/networking/vnic/sriov/rt-kernel/{vm_name}.xml")
                runcmd(f"virsh start {vm_name}")
                print(f"rt_kernel_setup.py: \nstart guest {vm_name}")
                logger.info("rt_kernel_setup.py: \nstart guest {vm_name}")
            elif vm_name == vm_names[1]:
                with open(
                        f'/mnt/tests/kernel/networking/vnic/sriov/rt-kernel/rhel{key_args.get("vm_rhel_version")}.xml',
                        'r') as e:
                    data = e.read()
                vm_data = json.loads(json.dumps(xmltodict.parse(data, process_namespaces=True)))
                vm_data['domain']['name'] = f'{vm_name}'  # define vm name
                vm_data['domain']['uuid'] = generate_uuid()  # define a random uuid
                vm_data['domain']['vcpu']['#text'] = f"{key_args.get('vm_cpunum')}"  # define a vcpu number
                # define memory same sa node
                vm_data['domain']['numatune']['memory']['@nodeset'] = f"{key_args.get('numa_node')}"
                # define memory same sa node
                vm_data['domain']['numatune']['memnode']['@nodeset'] = f"{key_args.get('numa_node')}"
                # define vcpupin
                vcpu_pins = []
                for i in range(0, int(key_args.get('vm_cpunum'))):
                    vcpu_pin = {'@vcpu': f'{i}', '@cpuset': f'{got_isolation_cpu_on_numa_node_list.pop(0)}'}
                    vcpu_pins.append(vcpu_pin)
                vm_data['domain']['cputune']['vcpupin'] = vcpu_pins
                vm_data['domain']['cputune'].update(
                    {'emulatorpin': {'@cpuset': got_housekeeping_cpu_on_numa_node},
                     'emulatorsched': {'@scheduler': 'fifo', '@priority': '1'}})
                # define a vcpu  schedule priority
                vcpuscheds = []
                for i in range(1, int(key_args.get('vm_cpunum'))):
                    # remind vcpu 0 role as housekeeping
                    vcpusched = {'@vcpus': f'{i}', '@scheduler': 'fifo', '@priority': '1'}
                    vcpuscheds.append(vcpusched)
                vm_data['domain']['cputune'].update({'vcpusched': vcpuscheds})
                vm_data['domain']['cpu']['numa']['cell']['@cpus'] = f"0-{int(key_args.get('vm_cpunum')) - 1}"
                # modify disk file
                vm_data['domain']['devices']['disk']['source']['@file'] = f"{vm_image_url[1]}"
                # modify network device
                interface_list = []
                interface1 = {'@type': 'bridge', 'mac': {'@address': f"{key_args.get('mac4vm2')}"},
                              'source': {'@bridge': 'virbr0'}, 'target': {'@dev': 'vnet0'},
                              'model': {'@type': 'virtio'}, 'alias': {'@name': 'net0'},
                              'address': {'@type': 'pci', '@domain': '0x0000', '@bus': '0x03',
                                          '@slot': '0x00', '@function': '0x0'}}
                interface_list.append(interface1)
                vm_data['domain']['devices']['interface'] = interface_list
                with open(f'/mnt/tests/kernel/networking/vnic/sriov/rt-kernel/{vm_name}.xml', 'w') as a:
                    a.write(xmltodict.unparse(vm_data, pretty=True))
                runcmd(f"virsh define --file /mnt/tests/kernel/networking/vnic/sriov/rt-kernel/{vm_name}.xml")
                runcmd(f"virsh start {vm_name}")
                print(f"rt_kernel_setup.py: \nstart guest {vm_name}")
                logger.info(f"rt_kernel_setup.py: \nstart guest {vm_name}")

    elif key_args.get("enable_vm_xml_tuning") is None or key_args.get("enable_vm_xml_tuning") == 'no' \
            or key_args.get("vm_rhel_version") not in support_vm_xml_version \
            or (len(vm_names) * int(key_args.get('vm_cpunum'))) > len(got_isolation_cpu_on_numa_node_list):
        print("rt_kernel_setup.py: \nskip xml tunning, will use virt-install to create guest.")
        for vm_name in vm_names:
            # defined a client vm, vm_names[0] role as first guest, vm_names[1] role as second guest
            if vm_name == vm_names[0]:
                runcmd(f"virt-install \
                     --name {vm_name} \
                     --vcpus={key_args.get('vm_cpunum')} \
                     --ram=4096 \
                     --disk path={vm_image_url[0]},device=disk,bus=virtio,format=qcow2 \
                     --network bridge=virbr0,model=virtio,mac={key_args.get('mac4vm1')} \
                     --network bridge=virbr1,model=virtio,mac={key_args.get('mac4vm1if2')} \
                     --boot hd \
                     --accelerate \
                     --graphics vnc,listen=0.0.0.0 \
                     --force \
                     --os-variant=rhel-unknown \
                     --noautoconsol")
            elif vm_name == vm_names[1]:
                runcmd(f"virt-install \
                     --name {vm_name} \
                     --vcpus={key_args.get('vm_cpunum')} \
                     --ram=4096 \
                     --disk path={vm_image_url[1]},device=disk,bus=virtio,format=qcow2 \
                     --network bridge=virbr0,model=virtio,mac={key_args.get('mac4vm2')} \
                     --boot hd \
                     --accelerate \
                     --graphics vnc,listen=0.0.0.0 \
                     --force \
                     --os-variant=rhel-unknown \
                     --noautoconsol")
    else:
        print("rt_kernel_setup.py: \ndefine_vm_xml failed, please check it")
        sys.exit(1)


def check_huge_page(os_type, vm_name=None):
    """
    :param os_type: check host or vm
    :param vm_name: if os_type is vm, need vm name to run command
    :return: None
    """
    if os_type == 'host':
        check_string = runcmd('cat /proc/cmdline')
        if 'default_hugepagesz=1G' in check_string:
            print('rt_kernel_setup.py: \nConfigure hugepagesize successed.')
        else:
            print('rt_kernel_setup.py: \nConfigure hugepagesize failed, please check reboot procress.')
    elif os_type == 'vm':
        check_information = runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "cat /proc/cmdline"')
        check_string = re.split(r'\[\w+\@\w+\s~\]#\s(cat \/proc\/cmdline\s+|echo \$\?\s+)', check_information)[2].strip(
            '\x1b[?2004l\n').strip('\x1b[?2004h').split()
        if 'default_hugepagesz=1G' in check_string:
            print('rt_kernel_setup.py: \nConfigure hugepagesize successed.')
            print("rt_kernel_setup.py: \nRuning check_huge_page the grubby --default-kernel.")
            runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
        else:
            print('rt_kernel_setup.py: \nConfigure hugepagesize failed, please check reboot procress.')


def check_system_version(os_type, vm_name=None):
    """
    :os_type: vm or host
    :vm_name: guest name
    """
    logger.info("rt_kernel_setup.py: \nRunning check_system_version function.")
    print("rt_kernel_setup.py: \nRunning check_system_version function.")
    if os_type == 'host':
        logger.info("rt_kernel_setup.py: \nCheck host system version.")
        print("rt_kernel_setup.py: \nCheck host system version.")
        rhel_release = runcmd('cat /etc/redhat-release')
        rhel_version = re.search(r'\d+\.\d+', rhel_release).group()
        logger.info(f"rt_kernel_setup.py: \nThe host rhel version is {rhel_version}.")
        print(f"rt_kernel_setup.py: \nThe host rhel version is {rhel_version}.")
    else:
        logger.info("rt_kernel_setup.py: \nCheck vm system version.")
        print("rt_kernel_setup.py: \nCheck vm system version.")
        rhel_release = runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "cat /etc/redhat-release"')
        rhel_version_string = re.split(r'\[\w+\@\w+\s~\]#\s(cat \/etc\/redhat-release\s+|echo \$\?\s+)', rhel_release)[
            2].strip('\x1b[?2004l\n').strip('\x1b[?2004h')
        rhel_version = re.search(r'\d+\.\d+', rhel_version_string).group()
        logger.info(f"rt_kernel_setup.py: \nThe vm rhel version is {rhel_version}.")
        print(f"rt_kernel_setup.py: \nThe vm rhel version is {rhel_version}.")
    return rhel_version


def check_vm_kernel(vm_name=None):
    """
    check default kernel equal boot kernel
    :param vm_name: check the vm name
    :return:
    """
    print("rt_kernel_setup.py: \nRunning check package installnation.")

    check_uname_kernel_string = runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "uname -r"')
    check_uname_kernel = check_uname_kernel_string.split("[root@localhost ~]# uname -r")[-1] \
        .split("[root@localhost ~]#")[0].strip().strip('echo $?')
    check_default_kernel_string = runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
    check_default_kernel = \
        check_default_kernel_string.split("[root@localhost ~]# grubby --default-kernel")[-1] \
            .split("[root@localhost ~]#")[0].strip().strip('echo $?').split('-', 1)[-1] \
            .strip()
    if check_uname_kernel == check_default_kernel:
        print(f'rt_kernel_setup.py: \n{vm_name} rt kernel install successes.')
        print(f'rt_kernel_setup.py: \nNow current running kernel is {check_uname_kernel},'
              f'default kernel is {check_default_kernel}.')
    else:
        print(f'rt_kernel_setup.py: \n{vm_name} default different between uname -r and grubby. need to reboot.')
    print("rt_kernel_setup.py: \nRun check_vm_kernel,grubby --default-kernel")
    runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')


def install_host(os_type, stage):
    if stage == '0':
        # instead of sriov_setup function in runtest.sh, this step will do in set_up.sh
        runcmd('rm -f /usr/local/bin/vmsh')
        runcmd('cp /mnt/tests/kernel/networking/common/tools/vmsh /usr/local/bin')
        # check host version
        rhel_version = check_system_version(os_type)

        if rhel_version is None:
            logger.error("can't check rhel version")
            print("can't check rhel version")
            sys.exit(1)
        elif rhel_version <= '8.6':
            # configure host repo, need add a new function to resloved rpm.
            with open('/mnt/tests/kernel/networking/vnic/sriov/rt-kernel/repo.json', 'r') as readprofile:
                repo_dict = json.load(readprofile)
            # Configure host repo
            configure_host_repo(repo_dict, rhel_version)

        # install libvrit tuna, tuned, rt-test package.
        install_package_host(rhel_version)
        # Configure Huge Page
        configure_huge_page(os_type, vm_name=None)
        # Configure cpu tuning
        configure_cpu_isolate('host', rhel_version, vm_name=None)
        runcmd('/usr/bin/rhts-reboot')
    # REBOOT
    elif stage == '1':
        check_huge_page(os_type)
        runcmd('/usr/sbin/iptables -F')
        runcmd('/usr/sbin/ip6tables -F')
        runcmd('systemctl stop firewalld')


def install_vm(os_type, **key_args):
    """
    :param os_type: need to set 'vm'
    :param **key_args: Receives the following parameters, vm_names, mac4vm1, mac4vm1if2, mac4vm2, vm_cpunum,
    rhel_image_name, enable_default_yum, vm_kernel_name, brew_task_id, kernel_repo, enable_vm_xml_tuning, test_nic
    """
    # Donwload vm image, vm_rhel_version, vm_names need shell parameter to transfer
    if key_args.get('vm_names') is None:
        print(f"rt_kernel_setup.py: \ninstall_vm can't got vm name. please check it. {key_args.get('vm_names')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm can't got vm name. please check it. {key_args.get('vm_names')}")
        sys.exit(1)
    else:
        print(f"rt_kernel_setup.py: \ninstall_vm got vm name {key_args.get('vm_names')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got vm name {key_args.get('vm_names')}")
    if key_args.get('rhel_image_name') is None:
        print(f"rt_kernel_setup.py: \ninstall_vm can't got rhel_image_name. please check it. "
              f"{key_args.get('rhel_image_name')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm can't got rhel_image_name. please check it. "
                    f"{key_args.get('rhel_image_name')}")
        sys.exit(1)
    else:
        print(f"rt_kernel_setup.py: \ninstall_vm got vm name {key_args.get('rhel_image_name')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got vm name {key_args.get('rhel_image_name')}")
    if key_args.get('mac4vm1') is not None:
        print(f"rt_kernel_setup.py: \ninstall_vm got mac4vm1 {key_args.get('mac4vm1')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got mac4vm1 {key_args.get('mac4vm1')}")
    if key_args.get('mac4vm1if2') is not None:
        print(f"rt_kernel_setup.py: \ninstall_vm mac4vm1if2 {key_args.get('mac4vm1if2')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm mac4vm1if2 {key_args.get('mac4vm1if2')}")
    if key_args.get('mac4vm2') is not None:
        print(f"rt_kernel_setup.py: \ninstall_vm got mac4vm2 {key_args.get('mac4vm2')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got mac4vm2 {key_args.get('mac4vm2')}")
    if key_args.get('vm_cpunum') is not None:
        print(f"rt_kernel_setup.py: \ninstall_vm got vm_cpunum {key_args.get('vm_cpunum')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got vm_cpunum {key_args.get('vm_cpunum')}")
    if key_args.get('enable_default_yum') is not None:
        print(f"rt_kernel_setup.py: \ninstall_vm got enable_default_yum {key_args.get('enable_default_yum')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got enable_default_yum {key_args.get('enable_default_yum')}")
    if key_args.get('vm_kernel_name') is not None:
        print(f"rt_kernel_setup.py: \ninstall_vm got vm_kernel_name {key_args.get('vm_kernel_name')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got vm_kernel_name {key_args.get('vm_kernel_name')}")
    if key_args.get('brew_task_id') is not None:
        print(f"rt_kernel_setup.py: \ninstall_vm got brew_task_id {key_args.get('brew_task_id')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got brew_task_id {key_args.get('brew_task_id')}")
    if key_args.get('kernel_repo') is None:
        print(f"rt_kernel_setup.py: \ninstall_vm got kernel_repo {key_args.get('kernel_repo')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got kernel_repo {key_args.get('kernel_repo')}")
    if key_args.get('enable_vm_xml_tuning') is None:
        print(f"rt_kernel_setup.py: \ninstall_vm got enable_vm_xml_tuning {key_args.get('enable_vm_xml_tuning')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got enable_vm_xml_tuning {key_args.get('enable_vm_xml_tuning')}")
    if key_args.get('test_nic') is None:
        print(f"rt_kernel_setup.py: \ninstall_vm got kernel_repo {key_args.get('test_nic')}")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm got kernel_repo {key_args.get('test_nic')}")

    vm_image_url = download_vm_image(vm_names=key_args.get('vm_names'), rhel_image_name=key_args.get('rhel_image_name'))
    if key_args.get('vm_kernel_name') is not None:
        vm_rhel_version = re.search(r'el(\d)', key_args.get('vm_kernel_name'))
        if vm_rhel_version is not None:
            vm_rhel_version = vm_rhel_version.group()[2:]
        else:
            print(f"rt_kernel_setup.py: \ninstall_vm. \n can't found kernel version")
            logger.info(f"rt_kernel_setup.py: \ninstall_vm. \n can't found kernel version")
            sys.exit(1)
    else:
        virt_get_kernel_result = \
            runcmd(f"/usr/bin/virt-get-kernel -a /var/lib/libvirt/images/{key_args.get('rhel_image_name')}")
        vm_rhel_version = re.search(r'el(\d)', virt_get_kernel_result)
        if vm_rhel_version is not None:
            vm_rhel_version = vm_rhel_version.group()[2:]
        else:
            print(f"rt_kernel_setup.py: \ninstall_vm. \n can't found kernel version")
            logger.info(f"rt_kernel_setup.py: \ninstall_vm. \n can't found kernel version")
            sys.exit(1)
    vm_rhel_version = str(vm_rhel_version)

    # define vm xml, vm_names, mac4vm1, mac4vm1if2, mac4vm2, vm_cpunum, test_nic need shell script to transfer
    if key_args.get('enable_vm_xml_tuning') == 'yes' and key_args.get('test_nic') is not None or key_args.get('test_nic') != "mac2name-error":
        print(f"rt_kernel_setup.py: \ninstall_vm. \n try to got the numa node of test nic")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm. \n try to got the numa node of test nic")
        try:
            numa_node = runcmd(f"cat /sys/class/net/{key_args.get('test_nic')}/device/numa_node")
        except Exception as a:
            print('rt_kernel_setup.py: \n', a)
            sys.exit(1)
    else:
        print(f"rt_kernel_setup.py: \ninstall_vm. \n got nic failed, test nic is {key_args.get('test_nic')}. please check it!!!")
        logger.info(f"rt_kernel_setup.py: \ninstall_vm. \n got nic failed, test nic is {key_args.get('test_nic')}. please check it!!!")
        numa_node = None

    for vm_name in key_args.get('vm_names'):
        runcmd(f"virsh shutdown {vm_name}")
        runcmd("sleep 5")
        runcmd(f"virsh undefine {vm_name}")
        runcmd("sleep 5")

    # transfer parameters: vm_names, mac4vm1, mac4vm1if2, mac4vm2, image_disk_urls, numa_node, vm_cpunum,
    # vm_rhel_version, enable_vm_xml_tuning
    define_vm_xml(vm_image_url, key_args.get('vm_names'), numa_node=numa_node, vm_rhel_version=vm_rhel_version,
                  mac4vm1=key_args.get('mac4vm1'), mac4vm1if2=key_args.get('mac4vm1if2'),mac4vm2=key_args.get('mac4vm2')
                  ,vm_cpunum=key_args.get('vm_cpunum'), enable_vm_xml_tuning=key_args.get('enable_vm_xml_tuning'))
    # vm ready to next step
    # wait for vm start
    runcmd('sleep 100')
    for vm_name in key_args.get('vm_names'):
        print("rt_kernel_setup.py: \nVM start configure")
        # configure vm repo
        configure_vm_repo(vm_name, vm_rhel_version, key_args.get('kernel_repo'))
        print("rt_kernel_setup.py: \nPrepare to install package in vm.")
        logger.info(f'rt_kernel_setup.py:  \nPrepare to install package in vm.')
        runcmd('sleep 5')
        # install vm rt-kernel
        logger.info("rt_kernel_setup.py: begin install_package_vm function.")
        install_package_vm(vm_name, vm_kernel_name=key_args.get('vm_kernel_name'),
                           enable_default_yum=key_args.get('enable_default_yum'),
                           brew_task_id=key_args.get('brew_task_id'), kernel_repo=key_args.get('kernel_repo'))
        # configure hugepage
        configure_huge_page(os_type, vm_name)
        # configure vm cpu isolate
        rhel_version = check_system_version(os_type, vm_name)
        print(f"rt_kernel_setup.py: \nAfter check_system_version. \n the system version is {rhel_version}")
        logger.info(f'rt_kernel_setup.py:  \nAfter check_system_version. \n the system version is {rhel_version}')
        configure_cpu_isolate(os_type, rhel_version, vm_name, key_args.get('vm_cpunum'))
        runcmd('sleep 5')
        print("rt_kernel_setup.py: \nAfter configure_cpu_isolate.")
        logger.info(f'rt_kernel_setup.py: \nAfter configure_cpu_isolate.')
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
        runcmd(f'virsh reboot {vm_name}')
        runcmd('sleep 100')
        print("rt_kernel_setup.py: \nAfter vm reboot progress.")
        logger.info('rt_kernel_setup.py: \nAfter vm reboot progress.')
        runcmd(f'/usr/local/bin/vmsh run_cmd {vm_name} "grubby --default-kernel"')
        check_huge_page(os_type, vm_name)
        check_vm_kernel(vm_name)
    # else:
    #     print("rt_kernel_setup.py: \nVm_cpunum over host_cpu_number, please reduce vm number or vcpu number.")
    #     logger.info("rt_kernel_setup.py: \nVm_cpunum over host_cpu_number, please reduce vm number or vcpu number.")
    #     sys.exit(1)


"""
stage=None, vm_names=None, mac4vm1=None, mac4vm1if2=None, mac4vm2=None, vm_cpunum=None,
         rhel_image_name=None, enable_default_yum=None, vm_kernel_name='None', brew_task_id='None', kernel_repo='None',
         enable_vm_xml_tuning=None
"""


def main(os_type, **key_args):
    """
    if install host, only need os_type and stage.
    if install vma, will use vm_names, mac4vm1, mac4vm1if2, mac4vm2, vm_cpunum,
    rhel_image_name, enable_default_yum, vm_kernel_name, brew_task_id, kernel_repo, enable_vm_xml_tuning, test_nic
    :return:
    """

    if os_type == 'host':
        if key_args.get('stage') is not None and key_args.get('stage') in ['0', '1']:
            install_host(os_type, stage=key_args.get('stage'))
        else:
            print(f"stage must input 0 or 1")
            sys.exit(1)
    elif os_type == 'vm':
        install_vm(os_type, vm_names=key_args.get('vm_names'), mac4vm1=key_args.get('mac4vm1'),
                   mac4vm1if2=key_args.get('mac4vm1if2'), mac4vm2=key_args.get('mac4vm2'),
                   vm_cpunum=key_args.get('vm_cpunum'), rhel_image_name=key_args.get('rhel_image_name'),
                   enable_default_yum=key_args.get('enable_default_yum'), vm_kernel_name=key_args.get('vm_kernel_name'),
                   brew_task_id=key_args.get('brew_task_id'), kernel_repo=key_args.get('kernel_repo'),
                   enable_vm_xml_tuning=key_args.get('enable_vm_xml_tuning'), test_nic=key_args.get('test_nic'))
    else:
        print(f"os_type need input host or vm")
        sys.exit(1)
