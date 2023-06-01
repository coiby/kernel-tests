#!/usr/bin/env python3
import os
import sys
import time
import inspect
import shutil as sh
from envbash import load_envbash
from plumbum import local
import subprocess as sp
import re
import tools
import xmltool
from functools import wraps
from beaker_cmd import (bash, enter_phase, log, log_and_run, pushd, run,
                        send_command, set_check,rl_fail,rl_pass,
                        sync_set,sync_wait,basic_send_command)
from lib.lib_sriov import LIB_SRIOV as pysriov
import socket

case_path = os.environ.get("CASE_PATH")
system_version_id = int(os.environ.get("SYSTEM_VERSION_ID"))
my_tool = tools.Tools()
xml_tool = xmltool.XmlTool()
client_target = "CLIENT"
server_target = "SERVER"
dpdk_test_option = os.getenv("DPDK_TEST_OPTION")
str_dpdk_version = os.environ["DPDK_VERSION"]
dpdk_verion = int(str_dpdk_version[0:2])
dpdk_minor_version = int(str_dpdk_version[3:5])
dut_nic_driver = os.getenv("NIC_DRIVER")

def load_env():
    log(sys.path)
    load_envbash(case_path + "/env.sh")

def test_item_check(f):
    @wraps(f)
    def check_itemlist(*args, **kwargs):
        test_item_list = os.getenv("TEST_ITEM_LIST")
        f_name = f.__name__
        if test_item_list == "all" or f_name in test_item_list:
            with enter_phase(f_name):
                f(*args, **kwargs)
        else:
            log(f"SKIP {f_name} test")
    return check_itemlist

def check_install(pkg_name):
    run(f"""rpm -q {pkg_name} || yum -y install {pkg_name}""")
    pass

def py3_run(cmd,str_ret_val="0"):
    run(cmd,str_ret_val)
    pass

@set_check(0)
def add_yum_profiles():
    if system_version_id < 80:
        epel_url = "http://download.lab.bos.redhat.com/rcm-guest/puddles/OpenStack/rhos-release/rhos-release-latest.noarch.rpm"
        run(f"rpm -q rhos-release || yum -y install {epel_url}")
        if not os.path.exists("/etc/yum.repos.d/rhos-release-13.repo"):
            with pushd(case_path):
                sh.copy("rhos-release-13.repo", "/etc/yum.repos.d/")
        run("rpm --import 'http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF'")
        data = """
        [tuned]
        name=Tuned development repository for RHEL-7
        baseurl=https://fedorapeople.org/~jskarvad/tuned/devel/repo/
        enabled=1
        gpgcheck=0
        skip_if_unavailable=1
        [mono-repo]
        name=mono-repo
        baseurl=http://download.mono-project.com/repo/centos/
        enabled=1
        gpgcheck=0
        skip_if_unavailable=1
        """
        data = "".join([i.strip() + '\n' for i in data.split('\n') if i != ''])
        local.path("/etc/yum.repos.d/tuned.repo").write(data, mode="w")
    else:
        run("advanced_qemu_install")

#czmq-devel
@set_check(0)
def install_package():
    basic_pack = """
    bc
    lshw
    pciutils
    wget
    git
    gcc
    make
    lsof
    nmap-ncat
    tcpdump
    expect
    ethtool
    yum-utils
    scl-utils
    tmux
    tar
    tuna
    openssl
    openssl-devel
    sysstat
    libnl3-devel
    tuned-profiles-cpu-partitioning
    """.split()
    for pack in basic_pack:
        check_install(pack)

    if system_version_id < 80:
        check_install("qemu-img-rhev")
        check_install("qemu-kvm-common-rhev")
        check_install("qemu-kvm-rhev")
        check_install("qemu-kvm-tools-rhev")
    else:
        check_install("qemu-kvm")
        check_install("qemu-img")
    #for virt packages install
    if system_version_id < 90:
        virt_packs = """
        libvirt
        libvirt-devel
        virt-install
        virt-manager
        virt-viewer
        libguestfs-tools
        """.split()
    else:
        virt_packs = """
        libvirt
        libvirt-devel
        virt-install
        virt-viewer
        libguestfs-tools
        """.split()

    for pack in virt_packs:
        check_install(pack)

    #workaround for bug https://bugzilla.redhat.com/show_bug.cgi?id=2057769
    if system_version_id >= 90:
        run("rm -f /usr/share/qemu/firmware/50-edk2-ovmf-amdsev.json","0,1")

    if system_version_id >= 90:
        check_install("guestfs-tools")

    # for qemu bug that can not start qemu
    if "hugetlbfs" in open("/etc/group").read():
        local.path("/etc/libvirt/qemu.conf").write("group = 'hugetlbfs'", mode="a+")
    run("systemctl restart libvirtd")
    run("systemctl start virtlogd.socket")

    # work around for failure of virt-install
    run("chmod 666 /dev/kvm")
    pass

@set_check(1)
def get_nic_name_from_mac(mac_addr):
    return my_tool.get_nic_name_from_mac(mac_addr)

@set_check(1)
def get_pmd_masks(str_cpus):
    return my_tool.get_pmd_masks(str_cpus)

@set_check(1)
def get_isolate_cpus(nic_name):
    return my_tool.get_isolate_cpus_with_nic(nic_name)

@set_check(0)
def config_isolated_cpu_and_Gb_hugepage(str_cpus, num_hpage):
    run("rpm -q grubby || yum -y install grubby")
    run("rpm -qa | grep tuned-profiles-cpu-partitioning || yum -y install tuned-profiles-cpu-partitioning")
    local.path("/etc/tuned/cpu-partitioning-variables.conf").write("isolated_cores={}".format(str_cpus))
    run("tuned-adm profile cpu-partitioning")
    run("cat /etc/tuned/cpu-partitioning-variables.conf")

    default_kernel = bash("grubby --default-kernel").value()
    cmd_line = f"""
    grubby --args='nohz=on default_hugepagesz=1G hugepagesz=1G \
    hugepages={num_hpage} intel_iommu=on iommu=pt \
    modprobe.blacklist=qedi modprobe.blacklist=qedf modprobe.blacklist=qedr pci=realloc' \
    --update-kernel {default_kernel}\
    """
    run(cmd_line)
    run("cat /etc/tuned/cpu-partitioning-variables.conf")
    pass


@set_check(0)
def install_driverctl():
    driverctl_url = os.environ.get("DRIVERCTL_URL")
    run(f"rpm -qa | grep `basename -s '.rpm' {driverctl_url}` || yum install -y {driverctl_url}")

@set_check(0)
def install_dpdk():
    if dpdk_test_option != "source":
        dpdk_url = os.environ.get("DPDK_URL")
        dpdk_tool_url = os.environ.get("DPDK_TOOL_URL")
        run(f"rpm -qa | grep `basename -s '.rpm' {dpdk_url}` || rpm -ivh {dpdk_url}")
        run(f"rpm -qa | grep `basename -s '.rpm' {dpdk_tool_url}` || rpm -ivh {dpdk_tool_url}","0,1")
        run(f"yum -y install {dpdk_url} {dpdk_tool_url}","0,1")
    else:
        print("################################")
        print("Current dpdk test item is source")
        print("################################")
        pass

def update_ssh_trust(remote_host):
    cmd = f"""
    mkdir -p ~/.ssh
    [[ -f ~/.ssh/known_hosts ]] || touch ~/.ssh/known_hosts
    [[ -f ~/.ssh/config ]] || touch ~/.ssh/config
    chmod 644 ~/.ssh/known_hosts
    chmod 644 ~/.ssh/config
    ssh-keyscan -t rsa {remote_host} >> ~/.ssh/known_hosts
    [[ ! -f ~/.ssh/id_rsa ]] && echo 'y' | ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
    """
    log_and_run(cmd,"0,1")
    pass

def get_bos_conn(remote_host,user,password):
    import paramiko
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(remote_host, username=user, password=password,allow_agent=False)
    return client

def git_clone_url(url):
    cmd = f"""
    git config --global --unset http.https://github.com.proxy
    git config --list
    git clone {url}
    git config --global --unset http.https://github.com.proxy
    git config --list
    """
    log_and_run(cmd,"0,5")
    pass

@set_check(0)
def init_physical_topo_without_switch():
    # init_netscout_tool()
    # init_netscout_config()
    server_port_one = os.environ.get("SERVER_PORT_ONE")
    client_port_one = os.environ.get("CLIENT_PORT_ONE")
    server_port_two = os.environ.get("SERVER_PORT_TWO")
    client_port_two = os.environ.get("CLIENT_PORT_TWO")
    if os.environ.get("CONN_TYPE") == "netscout":
        scout_connect(server_port_one, client_port_one)
        scout_connect(server_port_two, client_port_two)
    else:
        log("DO NOTHING,JUST FOR CUSTOMER PFT TEST")


@set_check(0)
def init_physical_topo_with_one_pair_ports():
    # init_netscout_tool()
    # init_netscout_config()
    server_port_one = os.environ.get("SERVER_PORT_ONE")
    client_port_one = os.environ.get("CLIENT_PORT_ONE")
    server_port_two = os.environ.get("SERVER_PORT_TWO")
    client_port_two = os.environ.get("CLIENT_PORT_TWO")
    if os.environ.get("CONN_TYPE") == "netscout":
        scout_connect(server_port_one, client_port_one)
        scout_disconnect(server_port_two, client_port_two)
    else:
        log("DO NOTHING,JUST FOR CUSTOMER PFT TEST")


def i_am_server():
    return os.environ["SERVERS"] == os.environ["HOSTNAME"]


def i_am_client():
    return os.environ["CLIENTS"] == os.environ["HOSTNAME"]


@set_check(0)
def config_hugepage():
    run("systemctl enable tuned && systemctl start tuned")
    if i_am_server():
        server_nic1_mac = os.environ.get("SERVER_NIC1_MAC")
        server_nic = my_tool.get_nic_name_from_mac(server_nic1_mac)
        server_cpu = get_isolate_cpus(server_nic)
        server_cpu = server_cpu.replace(" ", ",")
        config_isolated_cpu_and_Gb_hugepage(server_cpu, 48)
    elif i_am_client():
        client_nic1_mac = os.environ.get("CLIENT_NIC1_MAC")
        client_nic = my_tool.get_nic_name_from_mac(client_nic1_mac)
        client_cpu = get_isolate_cpus(client_nic)
        client_cpu = client_cpu.replace(" ", ",")
        config_isolated_cpu_and_Gb_hugepage(client_cpu, 48)
    else:
        log("Error Rule for config huge page")
    pass

def get_dpdk_devbind():
    if os.path.exists("/usr/share/dpdk/usertools/dpdk-devbind.py"):
        return "python3 /usr/share/dpdk/usertools/dpdk-devbind.py"
    elif os.path.exists("/usr/bin/dpdk-devbind.py"):
        return "python3 /usr/bin/dpdk-devbind.py"
    else:
        return None

def enable_dpdk_by_dpdk_devbind(nic_mac):
    nic_name = get_nic_name_from_mac(nic_mac)
    nic_businfo = my_tool.get_bus_from_name(nic_name)
    cmd = """
    modprobe vfio-pci
    modprobe vfio
    """
    run(cmd, "0,1")
    import ethtool
    driver_name = ethtool.get_module(nic_name)
    if driver_name == "mlx5_core":
        log("This Driver is Mallenox , So just return 0")
        return 0
    if dpdk_test_option != "source":
        dpdk_devbind_file = get_dpdk_devbind()
        if None != dpdk_devbind_file:
            log("using dpdk-devbind.py set the vfio-pci driver to nic")
            cmd = f"""
            {dpdk_devbind_file} -b vfio-pci {nic_businfo}
            {dpdk_devbind_file} --status
            """
            run(cmd)
        else:
            rl_fail("Can not find dpdk-devbind command")
    else:
        dpdk_devbind_file = os.getenv("COMPILE_DPDK_DEV_BIND")
        if os.path.exists(dpdk_devbind_file):
            log("Using Compile dpdk-devbind.py set the vfio-pci driver to nic")
            cmd = f"""
            {dpdk_devbind_file} -b vfio-pci {nic_businfo}
            {dpdk_devbind_file} --status
            """
            run(cmd)
        else:
            rl_fail("Can not find Compiled dpdk-devbind command ,Please check it")
    pass

def enable_dpdk_by_driverctl(nic_mac):
    nic_name = get_nic_name_from_mac(nic_mac)
    nic_businfo = my_tool.get_bus_from_name(nic_name)
    cmd = """
    modprobe vfio-pci
    modprobe vfio
    """
    run(cmd, "0,1")
    import ethtool
    driver_name = ethtool.get_module(nic_name)

    if driver_name == "mlx5_core":
        log("This Driver is Mallenox , So just return 0")
        return 0

    log("using driverctl set the vfio-pci driver to nic")
    cmd = f"""
    driverctl -v set-override {nic_businfo} vfio-pci
    sleep 3
    driverctl -v list-devices | grep vfio-pci
    """
    run(cmd)

def driver_bind(pci: str, driver: str, timeout: int = 5):
    device_path = "/sys/bus/pci/devices/" + pci
    steps = f"""
    modprobe {driver}
    echo {pci} > {device_path}/driver/unbind
    echo {driver} > {device_path}/driver_override
    echo {pci} > /sys/bus/pci/drivers/{driver}/bind
    """
    run(steps)

def enable_dpdk_by_driverctl_with_pci_addr(nic_businfo,mlx_driver_flag=False):
    cmd = """
    modprobe vfio-pci
    modprobe vfio
    """
    run(cmd, "0,1")
    if mlx_driver_flag == True:
        log("This Driver is Mallenox , So just return 0")
        return 0

    log("using driverctl set the vfio-pci driver to nic")
    cmd = f"""
    driverctl -v set-override {nic_businfo} vfio-pci
    sleep 3
    driverctl -v list-devices | grep vfio-pci
    """
    run(cmd)

@set_check(0)
def clear_dpdk_interface_by_devbind():
    if dpdk_test_option != "source":
        if bash("rpm -qa | grep dpdk-tools").value():
            dpdk_devbind_file = get_dpdk_devbind()
            if None != dpdk_devbind_file:
                bus_list = bash(fr"{dpdk_devbind_file} -s | grep  -E drv=vfio-pci\|drv=igb | awk '{{print $1}}'").value()
                print(bus_list)
                my_list = [ i for i in str(bus_list).split(os.linesep) if len(i.strip()) > 0 ]
                for i in my_list:
                    kernel_driver = bash(f"lspci -s {i} -v | grep Kernel  | grep modules  | awk '{{print $NF}}'").value()
                    run(f"{dpdk_devbind_file} -b {kernel_driver} {i}")
            else:
                rl_fail("Can not find dpdk-devbind.py,Please check it")
        else:
            rl_fail("Can not find dpdk-tools installed , Please check it ")
    else:
        dpdk_devbind_file = os.getenv("COMPILE_DPDK_DEV_BIND")
        bus_list = bash(fr"{dpdk_devbind_file} -s | grep  -E drv=vfio-pci\|drv=igb | awk '{{print $1}}'").value()
        print(bus_list)
        my_list = [ i for i in str(bus_list).split(os.linesep) if len(i.strip()) > 0 ]
        for i in my_list:
            kernel_driver = bash(f"lspci -s {i} -v | grep Kernel  | grep modules  | awk '{{print $NF}}'").value()
            run(f"{dpdk_devbind_file} -b {kernel_driver} {i}")
    pass

@set_check(0)
def clear_dpdk_interface_by_driverctl():
    bus_list = bash(r"driverctl -v list-devices|grep \*").value()
    print(bus_list)
    for i in str(bus_list).split(os.linesep):
        if len(i.strip()) > 0:
            pci_bus = i.split()[0]
            run(f"driverctl -v unset-override {pci_bus}")
    pass


@set_check(0)
def init_test_env():
    if i_am_server():
        server_nic1_name = get_nic_name_from_mac(os.environ["SERVER_NIC1_MAC"])
        os.environ["SERVER_NIC1_NAME"] = server_nic1_name
        os.environ["SERVER_NUMA"] = bash(f"cat /sys/class/net/{server_nic1_name}/device/numa_node").value()
    elif i_am_client():
        client_nic1_name = get_nic_name_from_mac(os.environ["CLIENT_NIC1_MAC"])
        os.environ["CLIENT_NIC1_NAME"] = client_nic1_name
        os.environ["CLIENT_NUMA"] = bash(f"cat /sys/class/net/{client_nic1_name}/device/numa_node").value()
    else:
        log("error server role")
        pass

    if i_am_server():
        log(":::: SERVER NUMA IS {}".format(os.environ["SERVER_NUMA"]))
    else:
        log(":::: CLIENT NUMA IS {}".format(os.environ["CLIENT_NUMA"]))
    pass

def attach_sriov_vf_to_vm(xml_file,vm,vf1_name,vf2_name):
    vf1_bus_info = my_tool.get_bus_from_name(vf1_name)
    vf2_bus_info = my_tool.get_bus_from_name(vf2_name)

    vf1_bus_info = vf1_bus_info.replace(":",'_')
    vf1_bus_info = vf1_bus_info.replace(".",'_')

    vf2_bus_info = vf2_bus_info.replace(":",'_')
    vf2_bus_info = vf2_bus_info.replace(".",'_')

    log(vf1_bus_info)
    log(vf2_bus_info)

    vf1_domain = vf1_bus_info.split('_')[0]
    vf1_bus    = vf1_bus_info.split('_')[1]
    vf1_slot   = vf1_bus_info.split('_')[2]
    vf1_func   = vf1_bus_info.split('_')[3]

    vf2_domain = vf2_bus_info.split('_')[0]
    vf2_bus    = vf2_bus_info.split('_')[1]
    vf2_slot   = vf2_bus_info.split('_')[2]
    vf2_func   = vf2_bus_info.split('_')[3]

    item = """
    <interface type='hostdev' managed='yes'>
        <mac address='{}'/>
        <driver name='vfio'/>
        <source >
            <address type='pci' domain='0x{}' bus='0x{}' slot='0x{}' function='0x{}'/>
        </source >
        <address type='pci' domain='{}' bus='{}' slot='{}' function='{}'/>
    </interface >
    """

    vf1_xml_path = os.getcwd() + "/vf1.xml"
    vf2_xml_path = os.getcwd() + "/vf2.xml"
    if os.path.exists(vf1_xml_path):
        os.remove(vf1_xml_path)
    if os.path.exists(vf2_xml_path):
        os.remove(vf2_xml_path)
    local.path(vf1_xml_path).touch()
    local.path(vf2_xml_path).touch()
    vf1_f_obj = local.path(vf1_xml_path)
    vf2_f_obj = local.path(vf2_xml_path)

    import xml.etree.ElementTree as xml

    vf1_format_list = ['52:54:00:11:8f:ea' ,vf1_domain, vf1_bus, vf1_slot, vf1_func, '0x0000', '0x03', '0x0', '0x0']
    vf1_novlan_item = item.format(*vf1_format_list)
    vf1_novlan_obj = xml.fromstring(vf1_novlan_item)
    vf1_f_obj.write(xml.tostring(vf1_novlan_obj))

    vf2_format_list = ['52:54:00:11:8f:eb' ,vf2_domain ,vf2_bus, vf2_slot ,vf2_func, '0x0000', '0x04', '0x0', '0x0']
    vf2_novlan_item = item.format(*vf2_format_list)
    vf2_novlan_obj = xml.fromstring(vf2_novlan_item)
    vf2_f_obj.write(xml.tostring(vf2_novlan_obj))

    cmd = f"""
    sleep 10
    echo "#################################################"
    cat {vf1_xml_path}
    echo "#################################################"
    cat {vf2_xml_path}
    echo "#################################################"
    virsh attach-device {vm} {vf1_xml_path}
    sleep 5
    virsh dumpxml {vm}
    sleep 10
    virsh attach-device {vm} {vf2_xml_path}
    sleep 5
    virsh dumpxml {vm}
    """
    log_and_run(cmd)

    return 0

@set_check(0)
def start_libvirtd_service():
    run("systemctl list-units --state=stop --type=service | grep libvirtd || systemctl restart libvirtd")

def clear_env():
    for i in local.path(case_path):
        if i.endswith("xml"):
            log(str(i))
            name = xml_tool.xml_get_name(str(i))
            if name:
                run(f"virsh list --all | grep {name} && virsh destroy {name}","0,1")
                run(f"virsh list --all | grep {name} && virsh undefine {name}","0,1")

    clear_all_vlan_and_bonding()
    clear_trex()
    clear_dpdk_interface_by_devbind()
    clear_dpdk_interface_by_driverctl()
    clear_hugepage()
    clean_ip_netns()

    if i_am_server():
        nic1_mac = os.environ["SERVER_NIC1_MAC"]
        nic2_mac = os.environ["SERVER_NIC2_MAC"]
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        vf_create(nic1_name, 0)
        vf_create(nic2_name, 0)
        #Here nic name may changed
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        cmd = f"""
        ip link set {nic1_name} down
        ip link set {nic2_name} down
        """
        run(cmd)
    elif i_am_client():
        nic1_mac = os.environ["CLIENT_NIC1_MAC"]
        nic2_mac = os.environ["CLIENT_NIC2_MAC"]
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        vf_create(nic1_name, 0)
        vf_create(nic2_name, 0)
        #Here nic name may changed
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        cmd = f"""
        ip link set {nic1_name} down
        ip link set {nic2_name} down
        """
        run(cmd)
    else:
        log("Here wrong rule")
    pass

def set_ip_link_up():
    if i_am_server():
        nic1_mac = os.environ["SERVER_NIC1_MAC"]
        nic2_mac = os.environ["SERVER_NIC2_MAC"]
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        vf_create(nic1_name, 0)
        vf_create(nic2_name, 0)
        #Here nic name may changed
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        cmd = f"""
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        sleep 10
        ip -d link show
        """
        run(cmd)
    elif i_am_client():
        nic1_mac = os.environ["CLIENT_NIC1_MAC"]
        nic2_mac = os.environ["CLIENT_NIC2_MAC"]
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        vf_create(nic1_name, 0)
        vf_create(nic2_name, 0)
        #Here nic name may changed
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
        cmd = f"""
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        sleep 10
        ip -d link show
        """
        run(cmd)
    else:
        log("Here wrong rule")
    pass

@set_check(0)
def disable_beaker_buildroot_repo():
    buildroot_file = "/etc/yum.repos.d/beaker-buildroot.repo"
    if os.path.exists(buildroot_file):
        with open(buildroot_file, mode="r+") as fd:
            all_data = fd.readlines()
            for i in range(0, len(all_data)):
                line = all_data[i]
                key = line.split("=")
                if "enabled" in key:
                    all_data[i] = "enabled=0\n"
                    break
            fd.seek(0)
            fd.truncate()
            log("".join(all_data))
            fd.write("".join(all_data))


@set_check(0)
def enable_dpdk_for_trex(nic1_mac,nic2_mac):
    install_dpdk()
    install_driverctl()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic1_businfo = my_tool.get_bus_from_name(nic1_name)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    nic2_businfo = my_tool.get_bus_from_name(nic2_name)

    cmd = f"""
    ip link set {nic1_name} down
    ip link set {nic2_name} down
    """
    run(cmd)

    cmd = """
    modprobe -r vfio-pci
    modprobe -r vfio
    modprobe vfio-pci
    modprobe vfio
    """
    run(cmd, "0,1")
    import ethtool
    driver_name = ethtool.get_module(nic1_name)
    if driver_name == "mlx5_core":
        log("This Driver is Mallenox , So just return 0")
        return 0
    if dpdk_test_option != "source":
        dpdk_devbind_file = get_dpdk_devbind()
        if None != dpdk_devbind_file:
            log("using dpdk-devbind.py set the vfio-pci driver to nic")
            cmd = f"""
            {dpdk_devbind_file} -b vfio-pci {nic1_businfo}
            sleep 3
            {dpdk_devbind_file} -b vfio-pci {nic2_businfo}
            {dpdk_devbind_file} --status
            """
            run(cmd)
        else:
            log("using driverctl set the vfio-pci driver to nic")
            cmd = f"""
            driverctl -v set-override {nic1_businfo} vfio-pci
            sleep 3
            driverctl -v set-override {nic2_businfo} vfio-pci
            sleep 3
            driverctl -v list-devices | grep vfio-pci
            """
            run(cmd)
    else:
        dpdk_devbind_file = os.getenv("COMPILE_DPDK_DEV_BIND")
        if os.path.exists(dpdk_devbind_file):
            log("using Compiled dpdk-devbind.py set the vfio-pci driver to nic")
            cmd = f"""
            {dpdk_devbind_file} -b vfio-pci {nic1_businfo}
            sleep 3
            {dpdk_devbind_file} -b vfio-pci {nic2_businfo}
            {dpdk_devbind_file} --status
            """
            run(cmd)
        else:
            log("using driverctl set the vfio-pci driver to nic")
            cmd = f"""
            driverctl -v set-override {nic1_businfo} vfio-pci
            sleep 3
            driverctl -v set-override {nic2_businfo} vfio-pci
            sleep 3
            driverctl -v list-devices | grep vfio-pci
            """
            run(cmd)

def clean_ip_netns():
    cmd = f"""
    ip -a netns del
    """
    run(cmd,"0,1")

def clear_hugepage():
    hugepage_dir = bash("mount -l | grep hugetlbfs | awk '{print $3}'").value()
    run(f"rm -rf {hugepage_dir}/*")
    return 0

def clear_trex():
    cmd = """
    pkill t-rex-64
    pkill t-rex-64
    pkill _t-rex-64
    pkill _t-rex-64
    """
    run(cmd, "0,1")
    pass

def clear_trex_and_free_hugepage():
    clear_trex()
    clear_hugepage()
    pass

def clear_container_env():
    cmd = f"""
    podman kill -a
    podman pod rm -a -f
    podman rm -a
    podman rmi -a
    """
    run(cmd,"0,1,2,125")
    pass

def clear_all_vlan_and_bonding():
    cmd = f"""
    modprobe -r 8021q
    modprobe -r bonding
    """
    run(cmd,"0,1")

@set_check(0)
def vf_create_from_pf_mac(mac, num,vf_spoofchk,vf_trust):
    pf_name = get_nic_name_from_mac(mac)
    vf_create(pf_name, num,vf_spoofchk,vf_trust)
    vf_list = pysriov.sriov_get_vf_list(pf_name)
    return vf_list

def setup_vf_max_tx_rate(pf,num,max_tx_rate):
    run(f"ip li set {pf} up")
    if max_tx_rate != 0:
        for i in range(0, num):
            run(f"ip li set {pf} vf {i} max_tx_rate {max_tx_rate}")
    vf_list = pysriov.sriov_get_vf_list(pf)
    return vf_list

def setup_vf_vlan_qos(pf,num,vlan,qos):
    run(f"ip li set {pf} up")
    if qos != 0:
        for i in range(0, num):
            run(f"ip li set {pf} vf {i} vlan {vlan} qos {qos}")
    vf_list = pysriov.sriov_get_vf_list(pf)
    return vf_list

def vf_vlan_create_from_pf_mac(mac,num,vlan,vf_spoofchk,vf_trust,max_tx_rate,qos):
    pf_name = get_nic_name_from_mac(mac)
    vf_create(pf_name, num,vf_spoofchk,vf_trust)
    for i in range(num):
        run(f"ip li set {pf_name} vf {i} vlan {vlan}")
    setup_vf_max_tx_rate(pf_name,num,max_tx_rate)
    setup_vf_vlan_qos(pf_name,num,vlan,qos)
    vf_list = pysriov.sriov_get_vf_list(pf_name)
    return vf_list

# create vf from pf nic name with special num
@set_check(0)
def vf_create(pf, num,vf_spoofchk=False,vf_trust=True):
    run(f"ip li set {pf} up")
    pf_bus = pysriov.sriov_get_pf_bus_from_pf_name(pf)
    cmds = pysriov.sriov_create_vfs(pf_bus[0], num)
    log(cmds)
    # for some nic create speed is low so here wait some time
    time.sleep(5)
    if vf_spoofchk == True:
        for i in range(0, num):
            run(f"ip li set {pf} vf {i} spoofchk on")
    else:
        for i in range(0, num):
            run(f"ip li set {pf} vf {i} spoofchk off")

    if vf_trust == True:
        for i in range(0, num):
            run(f"ip li set {pf} vf {i} trust on")
    else:
        for i in range(0, num):
            run(f"ip li set {pf} vf {i} trust off")
    pass

def vf_delete(pf_pci):
    pysriov.sriov_remove_vfs_from_pf_bus(pf_pci)
    pass

def get_nic_mac():
    if i_am_server():
        nic1_mac = os.getenv("SERVER_NIC1_MAC")
        nic2_mac = os.getenv("SERVER_NIC2_MAC")
    elif i_am_client():
        nic1_mac = os.getenv("CLIENT_NIC1_MAC")
        nic2_mac = os.getenv("CLIENT_NIC2_MAC")
    else:
        print("Error, Invalid system role, please check")
    return nic1_mac, nic2_mac


def get_nic_name():
    if i_am_server():
        nic1_mac = os.getenv("SERVER_NIC1_MAC")
        nic2_mac = os.getenv("SERVER_NIC2_MAC")
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
    elif i_am_client():
        nic1_mac = os.getenv("CLIENT_NIC1_MAC")
        nic2_mac = os.getenv("CLIENT_NIC2_MAC")
        nic1_name = get_nic_name_from_mac(nic1_mac)
        nic2_name = get_nic_name_from_mac(nic2_mac)
    else:
        print("Error, Invalid system role, please check")
        nic1_name = None
        nic2_name = None
    return nic1_name, nic2_name


def create_image_file(xml_file):
    start_libvirtd_service()
    img_guest = os.getenv("IMG_GUEST")
    dir_prefix="/tmp/"
    with pushd(case_path):
        guest_name = xml_tool.xml_get_name(xml_file)
        image_name = os.path.basename(img_guest)
        if os.path.exists(f"{dir_prefix}/{guest_name}.qcow2"):
            run(f"rm -f {dir_prefix}/{guest_name}.qcow2")
        pass
    cmd = f"""
    [[ -f {dir_prefix}/{image_name} ]] || wget -P {dir_prefix} {img_guest} > /dev/null 2>&1
    pushd {dir_prefix}
    cp {image_name} {guest_name}.qcow2
    sleep 5
    popd
    """
    run(cmd)
    return dir_prefix,guest_name


#guest_image : absolutely path to guest image
def update_guest_image_net_rules(guest_image):
    with pushd(case_path):
        udev_file = "60-persistent-net.rules"
        local.path(udev_file).touch()
        data = r"""
        ACTION=="add", SUBSYSTEM=="net", DRIVERS=="?*", ATTR{address}=="52:54:00:11:8f:ea", NAME="eth1"
        ACTION=="add", SUBSYSTEM=="net", DRIVERS=="?*", ATTR{address}=="52:54:00:bb:63:7a", NAME="eth2"
        """
        local.path(udev_file).write(data)
        run(f"virt-copy-in -a {guest_image} {udev_file} /etc/udev/rules.d/")


def update_guest_xml_cpu(xml_file):
    numa_node = os.environ.get("SERVER_NUMA")
    xml_tool.update_numa(xml_file,numa_node)
    vcpu_num = 4
    all_vcpus = my_tool.get_isolate_cpus_on_numa(numa_node)
    vcpus = all_vcpus.split(" ")[0:vcpu_num]
    log(f"vm1 numa node is {numa_node} vcpu num is {vcpu_num} vcpus {vcpus}")
    for i in range(vcpu_num):
        xml_tool.update_vcpu(xml_file,i,vcpus[i])

    xml_tool.update_vcpu_emulatorpin(xml_file,all_vcpus.split(" ")[vcpu_num+1])
    if system_version_id >= 92:
        xml_tool.remove_item_from_xml(xml_file,"./cputune/emulatorpin")

    cmd = f"""virsh define {case_path}/{xml_file}"""
    run(cmd)


def customize_guest(guest_name):
    cmd = f"""
    LIBGUESTFS_BACKEND=direct \
    virt-customize -d {guest_name} \
    --root-password password:redhat \
    --firstboot-command 'rm /etc/systemd/system/multi-user.target.wants/cloud-config.service' \
    --firstboot-command 'rm /etc/systemd/system/multi-user.target.wants/cloud-final.service' \
    --firstboot-command 'rm /etc/systemd/system/multi-user.target.wants/cloud-init-local.service' \
    --firstboot-command 'rm /etc/systemd/system/multi-user.target.wants/cloud-init.service' \
    --firstboot-command 'reboot'
    """
    run(cmd)


#guest_image : absolutely path to guest image
def install_dpdk_inside_guest(guest_image):
    #copy driverctl into guest image
    driverctl_url = os.environ.get("DRIVERCTL_URL")
    cmd = f"""
    rm -rf /root/driverctl_dir/
    mkdir -p /root/driverctl_dir/
    wget -P /root/driverctl_dir/ {driverctl_url} > /dev/null 2>&1
    virt-copy-in -a {guest_image} /root/driverctl_dir/ /root/
    sleep 10
    """
    run(cmd)
    if dpdk_test_option != "source":
        guest_dpdk_version = os.environ["GUEST_DPDK_VERSION"]
        guest_dpdk_url = os.environ["GUEST_DPDK_URL"]
        guest_dpdk_tool_url = os.environ["GUEST_DPDK_TOOL_URL"]

        log_info = f"""
        guest dpdk version {guest_dpdk_version}
        guest dpdk url {guest_dpdk_url}
        guest dpdk tool url {guest_dpdk_tool_url}
        """
        log(log_info)

        cmd = f"""
        sleep 10
        rm -rf /root/{guest_dpdk_version}
        mkdir -p /root/{guest_dpdk_version}
        wget -P /root/{guest_dpdk_version}/ {guest_dpdk_url} > /dev/null 2>&1
        wget -P /root/{guest_dpdk_version}/ {guest_dpdk_tool_url} > /dev/null 2>&1
        virt-copy-in -a {guest_image} /root/{guest_dpdk_version}/ /root/
        sleep 30
        """
        run(cmd)
    else:
        dpdk_source_packge = os.getenv("DPDK_SOURCE")
        dpdk_root_dir = os.getenv("DPDK_ROOT_DIR")
        log_info = f"""
        DPDK SOURCE PACKAGE {dpdk_source_packge}
        """
        log(log_info)
        guest_dpdk_dir="/root/guest_dpdk_source/"
        cmd = f"""
        rm -rf {guest_dpdk_dir}
        mkdir -p {guest_dpdk_dir}
        wget -P {guest_dpdk_dir} {dpdk_source_packge} > /dev/null 2>&1
        virt-copy-in -a {guest_image} {guest_dpdk_dir}  /root/
        virt-copy-in -a {guest_image} {case_path}/vm_compile_dpdk.sh /root/
        virt-copy-in -a {guest_image} /etc/yum.repos.d/beaker-CRB.repo /etc/yum.repos.d/
        virt-customize -a {guest_image} --delete {case_path}/
        virt-customize -a {guest_image} --mkdir {case_path}/
        virt-copy-in -a {guest_image} {dpdk_root_dir}  {case_path}/
        sleep 30
        """
        run(cmd)
    pass

def start_and_dumpxml_guest(guest_name):
    cmd = f"""
    virsh dumpxml {guest_name}
    virsh start {guest_name}
    sleep 60
    virsh dumpxml {guest_name}
    """
    run(cmd)


@set_check(0)
def destroy_guest(name="guest30032"):
    cmd = f"""
    virsh destroy {name}
    virsh undefine {name}
    """
    run(cmd)
    pass

def update_guest_isolate_cpus(guest_name):
    cmd = f"""
    stty rows 50 cols 132
    sed -i 's/GRUB_CMDLINE_LINUX=.*/& isolcpus=1,2/g' /etc/default/grub
    echo "isolated_cores=1,2" >> /etc/tuned/cpu-partitioning-variables.conf
    tuned-adm profile cpu-partitioning
    systemctl enable tuned
    systemctl start tuned
    echo "options vfio enable_unsafe_noiommu_mode=1" > /etc/modprobe.d/vfio.conf
    grub2-mkconfig -o /boot/grub2/grub.cfg
    grubby --args="default_hugepagesz=1G hugepagesz=1G" --update-kernel `grubby --default-kernel`
    grubby --info=ALL
    """
    pts = bash(f"virsh ttyconsole {guest_name}").value()
    all_result = my_tool.run_cmd_get_output(pts, cmd)
    log(all_result)
    bash(f"virsh reboot {guest_name}")
    return all_result

# {modprobe  vfio enable_unsafe_noiommu_mode=1}
def vm_install_dpdk(guest_name):
    log("guest compile and start testpmd now")
    cmd = fr"""
    stty rows 50 cols 132
    yum -y remove driverctl
    rpm -ivh /root/driverctl_dir/driverctl*.rpm
    """
    log(cmd)
    pts = bash(f"virsh ttyconsole {guest_name}").value()
    all_result = my_tool.run_cmd_get_output(pts, cmd)
    log(all_result)
    if dpdk_test_option != "source":
        guest_dpdk_version = os.getenv("GUEST_DPDK_VERSION")
        guest_dpdk_url = os.getenv("GUEST_DPDK_URL")
        guest_dpdk_tools_url = os.getenv("GUEST_DPDK_TOOL_URL")
        cmd = fr"""
        stty rows 50 cols 132
        /root/one_gig_hugepages.sh 4
        for i in `ls /root/{guest_dpdk_version}/`; do rpm -ivh /root/{guest_dpdk_version}/$i; done
        yum install -y {guest_dpdk_url}
        yum install -y {guest_dpdk_tools_url}
        driver=$(lspci -s 0000:03:00.0 -v | grep Kernel | grep modules | awk '{{print $NF}}')
        echo "Driver is "$driver
        grep "mlx" <<< $driver || driverctl -v set-override 0000:03:00.0 vfio-pci
        grep "mlx" <<< $driver || driverctl -v set-override 0000:04:00.0 vfio-pci
        """
        # log(cmd)
        pts = bash(f"virsh ttyconsole {guest_name}").value()
        all_result = my_tool.run_cmd_get_output(pts, cmd)
        log(all_result)
    else:
        dpdk_package_name=os.path.basename(os.getenv("DPDK_SOURCE"))
        cmd = fr"""
        stty rows 50 cols 132
        /root/one_gig_hugepages.sh 4
        driver=$(lspci -s 0000:03:00.0 -v | grep Kernel | grep modules | awk '{{print $NF}}')
        echo "Driver is "$driver
        grep "mlx" <<< $driver || driverctl -v set-override 0000:03:00.0 vfio-pci
        grep "mlx" <<< $driver || driverctl -v set-override 0000:04:00.0 vfio-pci
        """
        # log(cmd)
        pts = bash(f"virsh ttyconsole {guest_name}").value()
        all_result = my_tool.run_cmd_get_output(pts, cmd)
        log(all_result)
    pass


@set_check(0)
def install_trex_package(trex_url):
    with pushd(case_path):
        trex_name = os.path.basename(trex_url)
        #trex_dir = str(trex_name).split(".")[0]
        trex_dir = trex_name.strip(".tar.gz")
        cmd = f"""
        yum -y clean all
        yum -y install gcc git lshw pciutils wget
        yum -y install tuned-profiles-cpu-partitioning
        pushd {case_path}
        test -d {trex_dir} || wget {trex_url} > /dev/null 2>&1
        test -d {trex_dir} || tar -xvf {trex_name} > /dev/null 2>&1
        sleep 3
        popd
        """
        run(cmd,"0,1")


@set_check(0)
def install_trex_and_start(nic1_mac, nic2_mac, trex_url):
    update_beaker_tasks_repo()
    install_dpdk()
    install_driverctl()
    install_trex_package(trex_url)

    trex_name = os.path.basename(trex_url)
    trex_dir = trex_name.strip(".tar.gz")

    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    nic1_bus = my_tool.get_bus_from_name(nic1_name)
    nic2_bus = my_tool.get_bus_from_name(nic2_name)
    nic_bus = nic1_bus + " " + nic2_bus

    cmd = f"""
    pushd {case_path}/{trex_dir}
    rm -f /etc/trex_cfg.yaml
    sleep 3
    popd
    """
    run(cmd)

    cmd = f"""
    pushd {case_path}/{trex_dir}
    python3 --version
    python3 ./dpdk_setup_ports.py  -l
    python3 ./dpdk_setup_ports.py -c {nic_bus} --force-macs --no-ht -o /etc/trex_cfg.yaml
    systemctl enable tuned && systemctl start tuned
    popd
    """
    py3_run(cmd)

    enable_dpdk_for_trex(nic1_mac, nic2_mac)

    #./trex_daemon_server restart
    cmd = f"""
    pushd {case_path}/{trex_dir}
    unset core_list
    core_list=$(cat /etc/trex_cfg.yaml  | grep threads | awk -F ':' '{{print $NF}}' | tr -d ' []')
    IFS=',' read -r -a array <<< "$core_list"
    core_num=${{#array[@]}}
    #nohup ./t-rex-64  --no-ofed-check -c $core_num -i --iom 0 &
    setsid ./t-rex-64  --no-ofed-check -c $core_num -i --iom 0 --no-key --no-scapy-server > logfile 2>&1 < /dev/null &
    sleep 60
    cat logfile
    popd
    """
    run(cmd)
    pass

#########################################################################
#########################################################################
#########################################################################
#########################################################################
#########################################################################
#########################################################################
# Begin all function test
def start_host_testpmd(cmd,input_cmd):
    log(cmd)
    log(input_cmd)
    obj = sp.Popen(cmd,shell=True,stdin=sp.PIPE,stdout=sp.PIPE)
    return obj.communicate(input_cmd.encode())

def start_subprocess(cmd,sleep_time = 20):
    log(cmd)
    obj = sp.Popen(cmd,shell=True,stdin=sp.PIPE,stdout=sp.PIPE)
    time.sleep(sleep_time)
    return obj

def write_cmd_input(sp_obj,cmd_input,wait_time=20):
    log(cmd_input)
    sp_obj.stdin.write(cmd_input.encode())
    sp_obj.stdin.flush()
    import time
    time.sleep(wait_time)
    pass

def get_testpmd():
    dpdk_test_option = os.getenv("DPDK_TEST_OPTION")
    if dpdk_test_option == "source":
        testpmd = os.getenv("COMPILE_DPDK_TESTPMD")
    else:
        dpdk_version = os.environ["DPDK_VERSION"]
        major_verion = int(dpdk_version[0:2])
        if major_verion >= 20:
            testpmd = "dpdk-testpmd"
        else:
            testpmd = "testpmd"
    return testpmd

def get_l3fwd():
    dpdk_test_option = os.getenv("DPDK_TEST_OPTION")
    dpdk_l3fwd = "dpdk-l3fwd"
    if dpdk_test_option == "source":
        dpdk_l3fwd = os.getenv("COMPILE_DPDK_L3_FWD")
    return dpdk_l3fwd

def check_str_in_str(a,b):
    return str(a) in b or str(a).lower() in b or str(a).upper() in b

# It cover vfio-pci test
@test_item_check
def dpdk_bind_and_unbind_test():
    func_name = inspect.stack()[0][3]
    nic1_mac,_ = get_nic_mac()
    if i_am_server():
        with enter_phase(f"{func_name} enable dpdk by devbind"):
            enable_dpdk_by_dpdk_devbind(nic1_mac)
            clear_dpdk_interface_by_devbind()
            pass
        with enter_phase(f"{func_name} enable dpdk by driverctl"):
            enable_dpdk_by_driverctl(nic1_mac)
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        pass
    else:
        pass

@test_item_check
def dpdk_port_info_test():
    func_name = inspect.stack()[0][3]
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            cmd_input = f"""
            show port info all
            show port stats all
            """
            out,error = start_host_testpmd(cmd,cmd_input)
            log(out.decode())
            if error != None:
                log(error.decode())
                rl_fail(f"{cmd} and {cmd_input} exec failed")
            pass
        with enter_phase(f"{func_name}-check-result-and-clean"):
            if check_str_in_str(nic1_mac,out.decode()):
                rl_pass("nic1 mac check passed")
            else:
                rl_fail("nic1 mac check failed")

            if check_str_in_str(nic2_mac,out.decode()):
                rl_pass("nic2 mac check passed")
            else:
                rl_fail("nic2 mac check failed")
            #here clean interface
            clear_dpdk_interface_by_driverctl()
            pass

    elif i_am_client():
        pass
    else:
        pass

@test_item_check
def dpdk_port_blocklist_test():
    func_name = inspect.stack()[0][3]
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -b {bus1_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -b {bus1_info} -- -i --auto-start
                """
            cmd_input = f"""
            show port info all
            show port stats all
            """
            out,error = start_host_testpmd(cmd,cmd_input)
            log(out.decode())
            if error != None:
                log(error.decode())
                rl_fail(f"{cmd} and {cmd_input} exec failed")
            pass
        with enter_phase(f"{func_name}-check-result-and-clean"):
            # if check_str_in_str(nic1_mac,out.decode()):
            #     rl_fail("nic1 mac not in out string check failed")
            # else:
            #     rl_pass("nic1 mac not in out string check passed")

            # if check_str_in_str(nic2_mac,out.decode()):
            #     rl_pass("nic2 mac check passed")
            # else:
            #     rl_fail("nic2 mac check failed")
            #here clean interface
            clear_dpdk_interface_by_driverctl()
            pass

    elif i_am_client():
        pass
    else:
        pass


@test_item_check
def dpdk_port_state_change_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 20")
            pass
        with enter_phase(f"{func_name} check result"):
            out,error = sp_obj.communicate()
            if error != None:
                rl_fail(f"{cmd} start get failed , Please check")
            log(out.decode())
            if check_str_in_str('Port 0: link state change event',out.decode()):
                rl_pass("Port0 state change pass")
            else:
                rl_fail("Port0 state change fail")

            if check_str_in_str('Port 1: link state change event',out.decode()):
                rl_pass("Port1 state change pass")
            else:
                rl_fail("Port1 state change fail")

        with enter_phase(f"{func_name} clean dpdk"):
            clear_dpdk_interface_by_driverctl()
            pass
        with enter_phase(f"{func_name} restore network connection"):
            init_physical_topo_without_switch()
            run("sleep 30")
            sync_set(client_target, "restore_network_connection")
            pass
    elif i_am_client():
        sync_wait(server_target, sync_start)
        server_port_one = os.environ.get("SERVER_PORT_ONE")
        server_port_two = os.environ.get("SERVER_PORT_TWO")
        if os.environ.get("CONN_TYPE") == "netscout":
            scout_disconnect(server_port_one,server_port_two)
            import time
            time.sleep(10)
            scout_connect(server_port_one,server_port_two)
        else:
            log("Does not support current situation")
        sync_set(server_target,sync_end)
        sync_wait(server_target, "restore_network_connection")
        pass
    else:
        pass

@test_item_check
def dpdk_mtu_and_jumbo_packet_test(mtu_val = 1500,max_pkt_len = 9600):
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_" + str(mtu_val) + "_" + str(max_pkt_len) + "_start"
    sync_end = func_name + "_" + str(mtu_val) + "_" + str(max_pkt_len) + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --mbuf={ max_pkt_len + 200 } --max-pkt-len={max_pkt_len} --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --mbuf={ max_pkt_len + 200 } --max-pkt-len={max_pkt_len} --auto-start
                """
            cmd_input = f"""
            stop
            set verbose 9
            port stop all
            port config mtu 0 {mtu_val}
            port config mtu 1 {mtu_val}
            port start all
            start
            """
            sp_obj = start_subprocess(cmd)
            write_cmd_input(sp_obj,cmd_input)
            time.sleep(5)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            out, error = sp_obj.communicate()
            if None != error:
                print(error.decode())
                rl_fail(f"{cmd} --- {cmd_input} ---failed, Please check")
            print(out.decode())
            pass
        with enter_phase(f"{func_name} clean testpmd"):
            clear_dpdk_interface_by_driverctl()
            pass
        with enter_phase(f"{func_name} check result"):
            m = re.search(r'RX-total: [1-9][0-9]+',out.decode())
            if m == None:
                rl_fail(f"{func_name} check rx-total failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} check rx-total passed")
            m = re.search(r'TX-total: [1-9][0-9]+',out.decode())
            if m == None:
                rl_fail(f"{func_name} check tx-total failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} check tx-total passed")
            pass
        with enter_phase(f"{func_name} check bug 2182799"):
            m = re.search(r'i40e_set_mac_max_frame',out.decode())
            if m == None:
                rl_pass(f"{func_name} check bug 2182799 i40e_set_mac_max_frame pass")
            else:
                rl_fail(f"{func_name} check bug 2182799 i40e_set_mac_max_frame failed")
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu {max_pkt_len}
        ip link set {nic2_name} mtu {max_pkt_len}
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target, sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = mtu_val
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt) - 4 ) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv4 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = mtu_val
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt) - 4 ) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#https://doc.dpdk.org/dts/test_plans/checksum_offload_test_plan.html
@test_item_check
def dpdk_checksum_offload_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --enable-rx-cksum --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --enable-rx-cksum --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd_input = f"""
            stop
            set verbose 9
            set fwd csum
            port stop all
            csum set ip hw 0
            csum set udp hw 0
            csum set tcp hw 0
            csum set sctp hw 0
            csum set ip hw 1
            csum set udp hw 1
            csum set tcp hw 1
            csum set sctp hw 1
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd_input)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            pass
        with enter_phase(f"{func_name} check result"):
            out ,error = sp_obj.communicate(b"stop")
            if None != error:
                rl_fail(f"{func_name} start testpmd failed")
            print(out.decode())
            m = re.search(r'Bad-ipcsum: 0',out.decode())
            if m == None:
                rl_fail(f"{func_name} check rx-total failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} check rx-total passed")
            m = re.search(r'Bad-l4csum: 0',out.decode())
            if m == None:
                rl_fail(f"{func_name} check tx-total failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} check tx-total passed")
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv4 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            log("IPV6 does not have checksum")
            rl_pass(f"{func_name} IPV6 packets check")
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#dpdk test plan
#https://dpdk-test-plans.readthedocs.io/en/latest/
#https://doc.dpdk.org/dts/test_plans/
@test_item_check
def dpdk_tso_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --enable-rx-cksum --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --enable-rx-cksum --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            set fwd csum
            port stop all
            csum set ip hw 0
            csum set udp hw 0
            csum set tcp hw 0
            csum set sctp hw 0
            csum set ip hw 1
            csum set udp hw 1
            csum set tcp hw 1
            csum set sctp hw 1
            tso set 800 0
            tso set 800 1
            port start all
            start
            """
            log("Exec update testpmd command")
            log(cmd)
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime and check result"):
            write_cmd_input(sp_obj,"stop")
            out ,error = sp_obj.communicate(b"stop")
            if None != error:
                rl_fail(f"{func_name} start testpmd failed")
            print(out.decode())
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            #skip this for https://bugzilla.redhat.com/show_bug.cgi?id=1858215
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.inet import TCP
            from scapy.layers.inet import UDP
            size = 1514
            # pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")/UDP(sport=1021,dport=1021)
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'check ipv4 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.inet import TCP
            from scapy.layers.inet import UDP
            size = 1514
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")/UDP(sport=1021,dport=1021)
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#https://doc.dpdk.org/dts/test_plans/dpdk_gso_lib_test_plan.html
@test_item_check
def dpdk_gso_and_gro_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --enable-rx-cksum --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --enable-rx-cksum --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            set gso segsz 2000
            set port 0 gso on
            set port 1 gso on
            show port 0 gso
            show port 1 gso
            set port 0 gro on
            set port 1 gro on
            set gro flush 4
            show port 0 gro
            show port 1 gro
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
        with enter_phase(f"{func_name} stop runtime and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
            print(out.decode())
            m = re.search(r'Supported GSO types',out.decode())
            if m == None:
                rl_fail(f"{func_name} check gso type failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} check gso type passed")
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass

    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target, sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_rss_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --enable-rx-cksum --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --enable-rx-cksum --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            port config all rss all
            port config all rss default
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
        with enter_phase(f"{func_name} testpmd stop and check result"):
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
            print(out.decode())
        with enter_phase(f"{func_name} clear dpdk interface"):
            #skip for bug https://bugzilla.redhat.com/show_bug.cgi?id=1858735
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target, sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_broadcast_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            port start all
            start
            """
            log("Exec update testpmd command")
            log(cmd)
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
        with enter_phase(f"{func_name} check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Rx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Rx total result check pass")

            m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Tx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Tx total result check pass")
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = "FF:FF:FF:FF:FF:FF"
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = "FF:FF:FF:FF:FF:FF"
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_multicast_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Rx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Rx total result check pass")

            m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Tx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Tx total result check pass")
            pass
        with enter_phase(f"{func_name} check result"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = "01:00:5e:f8:f8:f8"
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            pkt.dst= "33:33:f8:f8:f8:f8"
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = "01:00:5e:f8:f8:f8"
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            pkt.dst= "33:33:f8:f8:f8:f8"
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_promisc_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            set promisc all on
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

# testpmd> set verbose 9
# testpmd> vlan set filter on
# testpmd> set fwd io
# Set mac packet forwarding mode
# testpmd> rx_vlan add 1 0
# testpmd> vlan set strip off 0
@test_item_check
def dpdk_vlan_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            #rx_vlan add all 0
            #rx_vlan add all 1
            cmd = f"""
            stop
            set verbose 9
            port stop all
            vlan set filter on 0
            vlan set filter on 1
            rx_vlan add 2 0
            rx_vlan add 2 1
            set fwd io
            vlan set strip off 0
            vlan set strip off 1
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            #write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Rx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Rx total result check pass")

            m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Tx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Tx total result check pass")
            pass
        with enter_phase(f"{func_name} clean dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} ether host {nic2_mac} and vlan -e -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} ether host {nic2_mac} and vlan -e -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#vlan set qinq on 0
@test_item_check
def dpdk_qinq_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            vlan set filter on
            set fwd io
            rx_vlan add 2 0
            rx_vlan add 2 1
            vlan set qinq on 0
            vlan set qinq on 1
            vlan set strip off 0
            vlan set strip off 1
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Rx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Rx total result check pass")

            m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Tx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Tx total result check pass")
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} ether host {nic2_mac} and vlan -e -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            # pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IP(src="1.1.1.1",dst="2.2.2.2")
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            size = 64
            # pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name}  ether host {nic2_mac} and vlan -e -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            # pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IP(src="1.1.1.1",dst="2.2.2.2")
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            size = 64
            # pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

# rx_vxlan_port add 4789 0
# rx_vxlan_port add 4789 1
@test_item_check
def dpdk_tunnel_vxlan_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            port stop all
            set verbose 9
            rx_vxlan_port add 4789 0
            rx_vxlan_port add 4789 1
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Rx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Rx total result check pass")

            m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Tx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Tx total result check pass")
            pass
        with enter_phase(f"{func_name} clean dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.inet import UDP
            from scapy.layers.l2 import Dot1Q
            from scapy.layers.vxlan import VXLAN
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")/UDP()/VXLAN()
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        #dpdk_tunnel_vxlan_test does not over ipv6 now ?
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.inet import UDP
            from scapy.layers.l2 import Dot1Q
            from scapy.layers.vxlan import VXLAN
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")/UDP()/VXLAN()
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#Ether()/IPv6(nh=47)/GRE()/IP()/UDP()/Raw('x'*40)
#Ether()/IP()/GRE()/IP(dst="0.0.0.0")/UDP()
#https://doc.dpdk.org/dts/test_plans/ipgre_test_plan.html
@test_item_check
def dpdk_tunnel_gre_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            port stop all
            set verbose 9
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Rx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Rx total result check pass")

            m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Tx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Tx total result check pass")
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} proto gre -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.inet import UDP
            from scapy.layers.l2 import Dot1Q
            from scapy.layers.vxlan import VXLAN
            from scapy.layers.l2 import GRE
            size = 128
            pkt = Ether()/IP()/GRE()/IP(dst="2.2.2.2")/UDP()
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} proto gre -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.inet import UDP
            from scapy.layers.l2 import Dot1Q
            from scapy.layers.vxlan import VXLAN
            from scapy.layers.l2 import GRE
            size = 128
            pkt = Ether()/IPv6()/GRE()/IPv6(dst="3000::200")/UDP()
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#https://doc.dpdk.org/guides/howto/virtio_user_as_exceptional_path.html
@test_item_check
def dpdk_virtio_user_as_exceptional_path_ipv4_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    print(bus2_info)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -n 4 -a {bus1_info} --vdev=virtio_user0,path=/dev/vhost-net,queue_size=1024 \
                -- -i --txd=1024 --rxd=1024
                """
            else:
                cmd = f"""
                {testpmd} -n 4 -w {bus1_info} --vdev=virtio_user0,path=/dev/vhost-net,queue_size=1024 \
                -- -i --txd=1024 --rxd=1024
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            port stop 0
            port config 0 rx_offload tcp_cksum on
            port config 0 rx_offload udp_cksum on
            port start 0
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sh_cmd = f"""
            ip ad ad 192.168.99.99/24 dev tap0
            ip li set tap0 up
            """
            run(sh_cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        sync_wait(server_target,sync_start)
        cmd = f"""
        ip ad flush {nic1_name}
        ip ad flush {nic2_name}
        ip ad ad 192.168.99.100/24 dev {nic1_name}
        ip link set {nic1_name} up
        """
        run(cmd)
        obj1 = bash("ping 192.168.99.99 -c 20")
        log(obj1.stdout)
        log(obj1.stderr)

        if obj1.code != 0:
            cmd = f"""
            ip ad flush {nic1_name}
            ip ad flush {nic2_name}
            ip ad ad 192.168.99.100/24 dev {nic2_name}
            ip link set {nic2_name} up
            """
            run(cmd)
            obj2 = bash("ping 192.168.99.99 -c 20")
            log(obj2.stdout)
            log(obj2.stderr)
        if obj1.code != 0 and obj2.code != 0:
            rl_fail("ping 192.168.99.99 -c 20 FAILED")
        else:
            rl_pass("ping 192.168.99.99 -c 20 PASSED")
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#https://doc.dpdk.org/guides/howto/virtio_user_as_exceptional_path.html
@test_item_check
def dpdk_virtio_user_as_exceptional_path_ipv6_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    print(bus2_info)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -n 4 -a {bus1_info} --vdev=virtio_user0,path=/dev/vhost-net,queue_size=1024 \
                -- -i --txd=1024 --rxd=1024
                """
            else:
                cmd = f"""
                {testpmd} -n 4 -w {bus1_info} --vdev=virtio_user0,path=/dev/vhost-net,queue_size=1024 \
                -- -i --txd=1024 --rxd=1024
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            port stop 0
            port config 0 rx_offload tcp_cksum on
            port config 0 rx_offload udp_cksum on
            port start 0
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sh_cmd = f"""
            ip ad ad 3000::100/64 dev tap0
            ip li set tap0 up
            """
            run(sh_cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        sync_wait(server_target,sync_start)
        cmd = f"""
        ip ad flush {nic1_name}
        ip ad flush {nic2_name}
        ip ad ad 3000::200/64 dev {nic1_name}
        ip link set {nic1_name} up
        """
        run(cmd)
        obj1 = bash("ping6 3000::100 -c 20")
        log(obj1.stdout)
        log(obj1.stderr)

        if obj1.code != 0:
            cmd = f"""
            ip ad flush {nic1_name}
            ip ad flush {nic2_name}
            ip ad ad 3000::200/64 dev {nic2_name}
            ip link set {nic2_name} up
            """
            run(cmd)
            obj2 = bash("ping6 3000::100 -c 20")
            log(obj2.stdout)
            log(obj2.stderr)
        if obj1.code != 0 and obj2.code != 0:
            rl_fail("ping6 3000::100 -c 20 FAILED")
        else:
            rl_pass("ping6 3000::100 -c 20 PASSED")
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#https://doc.dpdk.org/guides/sample_app_ug/l3_forward.html
#https://mails.dpdk.org/archives/users/2016-July/000783.html
#https://doc.dpdk.org/dts/test_plans/l3fwd_test_plan.html
#./dpdk-20.08/build/examples/dpdk-l3fwd -c 0xf -- -P -p 0x3  --config="(0,0,0),(0,1,1),(1,0,2),(1,1,3)"
@test_item_check
def dpdk_l3_forwarding_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    dpdk_l3fwd = get_l3fwd()
    if dpdk_test_option == "source":
        if i_am_server():
            with enter_phase(f"{func_name}"):
                clear_dpdk_interface_by_driverctl()
                enable_dpdk_by_driverctl(nic1_mac)
                enable_dpdk_by_driverctl(nic2_mac)
                cmd = f"""
                {dpdk_l3fwd} -c 0xf -w {bus1_info} -w {bus2_info} -- -P -p 0x3  --config="(0,0,0),(0,1,1),(1,0,2),(1,1,3)"
                """
                log(cmd)
                sp_obj = sp.Popen(cmd.split(),stdin=sp.PIPE,stdout=sp.PIPE)
                time.sleep(20)
                sync_set(client_target, sync_start)
                sync_wait(client_target,sync_end)
            with enter_phase(f"{func_name} stop l3fwd and check result"):
                sp_obj.terminate()
                out,error = sp_obj.communicate()
                if None != error:
                    print(f"{func_name} start testpmd failed")
                    print(error.decode())
                print(out.decode())
                pass
            with enter_phase(f"{func_name} clear dpdk interface"):
                clear_dpdk_interface_by_driverctl()
                pass
        elif i_am_client():
            cmd = f"""
            ip link set {nic1_name} mtu 9600
            ip link set {nic2_name} mtu 9600
            ip link set {nic1_name} up
            ip link set {nic2_name} up
            """
            run(cmd)
            sync_wait(server_target,sync_start)
            with enter_phase(f"{func_name} IPV4 packets check"):
                pkt_file_name = "abc.cap"
                cmd = f"""
                rm -f {pkt_file_name}
                tcpdump -i {nic1_name} host 2.2.2.2 -w {pkt_file_name} &
                sleep 3
                """
                run(cmd)
                send_pkt_num = 10
                from scapy import all
                from scapy.layers.l2 import Ether
                from scapy.utils import hexdump
                from scapy.sendrecv import sendp
                from scapy.layers.inet import IP
                size = 64
                pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
                pkt.dst = nic2_mac
                payload = max(0, size - len(pkt)) * 'x'
                pkt.add_payload(payload.encode())
                print(pkt.show())
                sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
                #here kill tcpdump and read capture file to get item number
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q  | wc -l`
                rlAssertGreaterOrEqual 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
            with enter_phase(f"{func_name} IPV6 packets check"):
                pkt_file_name = "abc.cap"
                cmd = f"""
                rm -f {pkt_file_name}
                tcpdump -i {nic1_name} host 3000::200 -w {pkt_file_name} &
                sleep 3
                """
                run(cmd)
                send_pkt_num = 10
                from scapy import all
                from scapy.layers.l2 import Ether
                from scapy.utils import hexdump
                from scapy.sendrecv import sendp
                from scapy.layers.inet6 import IPv6
                size = 64
                pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
                pkt.dst = nic2_mac
                payload = max(0, size - len(pkt)) * 'x'
                pkt.add_payload(payload.encode())
                print(pkt.show())
                sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
                #here kill tcpdump and read capture file to get item number
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q  | wc -l`
                rlAssertGreaterOrEqual 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
            sync_set(server_target,sync_end)
            pass
        else:
            pass
    else:
        log("Skip this test as no l3fwd exists")

@test_item_check
def dpdk_sriov_vf_multiple_queues_test(vf_spoofchk,vf_trust,rxq_num=16):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str + "-rxq_num-" + str(rxq_num)
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            txq_num = rxq_num
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --rxq={rxq_num} --txq={txq_num} --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --rxq={rxq_num} --txq={txq_num} --auto-start
                """
            sp_obj = start_subprocess(cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime and check result"):
            out ,error = sp_obj.communicate(b"stop")
            if None != error:
                rl_fail(f"{func_name} start testpmd failed")
            print(out.decode())
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.inet import TCP
            from scapy.layers.inet import UDP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")/UDP(sport=1021,dport=1021)
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertGreaterOrEqual 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.inet import TCP
            from scapy.layers.inet import UDP
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")/UDP(sport=1021,dport=1021)
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertGreaterOrEqual 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_vf_func_test(vf_spoofchk,vf_trust,max_tx_rate):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    if max_tx_rate == 0:
        vf_max_tx_rate_str = "-without-max-tx-rate-"
        enable_max_tx_rate = False
    else:
        vf_max_tx_rate_str = "-with-max-tx-rate-"
        enable_max_tx_rate = True
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str + vf_max_tx_rate_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            if enable_max_tx_rate == True:
                setup_vf_max_tx_rate(nic1_name,1,max_tx_rate)
                setup_vf_max_tx_rate(nic2_name,1,max_tx_rate)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime and check result"):
            out ,error = sp_obj.communicate(b"stop")
            if None != error:
                rl_fail(f"{func_name} start testpmd failed")
            print(out.decode())
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
        # with enter_phase(f"{func_name} check ip -s -d link "):
        #     cmd = f"""
        #     ip -s -d link show {nic1_name}
        #     ip -s -d link show {nic2_name}
        #     """
        #     run(cmd)
        #     pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.inet import TCP
            from scapy.layers.inet import UDP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")/UDP(sport=1021,dport=1021)
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertGreaterOrEqual 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.inet import TCP
            from scapy.layers.inet import UDP
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")/UDP(sport=1021,dport=1021)
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertGreaterOrEqual 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

# https://bugzilla.redhat.com/show_bug.cgi?id=2172738 reproducer
# dpdk-testpmd -l 45-60 -a 0000:31:01.0 -- -i --rxq=16 --txq=16
# flow create 0 ingress pattern eth / ipv4 / udp / gtpu / ipv6 / end actions rss func symmetric_toeplitz types ipv6 end key_len 0 queues end / end
# just for ice driver
@test_item_check
def dpdk_sriov_single_vf_test(vf_spoofchk,vf_trust,rxq_num=16):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str + "-rxq_num-" + str(rxq_num)
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list}")
            vf1_name = vf1_list[0]
            log(f"{vf1_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            log(f"{vf1_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            log(f"{bus1_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            txq_num = rxq_num
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -- -i --rxq={rxq_num} --txq={txq_num}
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -- -i --rxq={rxq_num} --txq={txq_num}
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            flow create 0 ingress pattern eth / ipv4 / udp / gtpu / ipv6 / end actions rss func symmetric_toeplitz types ipv6 end key_len 0 queues end / end
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            out,error = sp_obj.communicate()
            if None != error:
                print(error.decode())
            print(out.decode())
            from bash import bash
            cmd = f"""
            journalctl --no-pager -l | grep dpdk-testpmd | grep 'Return failure'
            """
            ret_value = bash(cmd).value()
            if 'Return failure' in ret_value:
                rl_fail("check the journal log find the return error")
            else:
                rl_pass("testpmd run success")
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        sync_wait(server_target,sync_start)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#rhel9 still has this issue until now .2023.02.03
#https://bugzilla.redhat.com/show_bug.cgi?id=2166812
#current only test spoofchk on and trust off
@test_item_check
def dpdk_sriov_vf_vlan_for_bug_2131310_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            vlan set filter on 0
            vlan set filter on 1
            rx_vlan add 2 0
            rx_vlan add 2 1
            set fwd io
            vlan set strip on 0
            vlan set strip on 1
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            if vf_trust == True:
                m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Rx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Rx total result check pass")

                m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Tx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Tx total result check pass")
                pass
            #VLAN tci=0x221 - hw ptype: L2_ETHER_ARP  - sw ptype: L2_ETHER  - l2_len=14 - Receive queue=0x0  ol_flags: PKT_RX_VLAN PKT_RX_L4_CKSUM_GOOD PKT_RX_IP_CKSUM_GOOD PKT_RX_VLAN_STRIPPED
            # if "VLAN tci" in out.decode() and "PKT_RX_VLAN_STRIPPED" in out.decode():
            if "VLAN tci" in out.decode() and "VLAN_STRIPPED" in out.decode():
                rl_pass(f"{func_name} vlan tci and rx vlan strip check pass")
            else:
                rl_fail(f"{func_name} vlan tci and rx vlan strip check failed")
                pass
        with enter_phase(f"{func_name} check result"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -nevv host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            # https://bugzilla.redhat.com/show_bug.cgi?id=2079683
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            # pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            tcpdump -r abc.cap -nevv -q
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -nevv host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(vlan=2)/IPv6(src="3000::100",dst="3000::200")
            # pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#current only test spoofchk on and trust off
@test_item_check
def dpdk_sriov_vf_config_vsi_queues_bug2137378_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --rxq=1 --txq=12 --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --rxq=1 --txq=12 --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            if vf_trust == True:
                m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Rx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Rx total result check pass")

                m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Tx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Tx total result check pass")
                pass
        with enter_phase(f"{func_name} check result"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -nevv host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            # pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            tcpdump -r abc.cap -nevv -q
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -nevv host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 2
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#current only test spoofchk off and trust on
@test_item_check
def dpdk_sriov_vf_bug2091552_test(vf_spoofchk=False,vf_trust=True):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,2,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,2,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf11_name = vf1_list[0]
            vf12_name = vf1_list[1]
            vf21_name = vf2_list[0]
            vf22_name = vf2_list[1]
            log(f"{vf11_name} and {vf12_name}")
            log(f"{vf21_name} and {vf22_name}")
            vf11_mac = pysriov.sriov_get_mac_from_name(vf11_name)
            vf12_mac = pysriov.sriov_get_mac_from_name(vf12_name)
            vf21_mac = pysriov.sriov_get_mac_from_name(vf21_name)
            vf22_mac = pysriov.sriov_get_mac_from_name(vf22_name)
            log(f"{vf11_mac} and {vf12_mac}")
            log(f"{vf21_mac} and {vf22_mac}")
            bus11_info = my_tool.get_bus_from_name(vf11_name)
            bus12_info = my_tool.get_bus_from_name(vf12_name)
            bus21_info = my_tool.get_bus_from_name(vf21_name)
            bus22_info = my_tool.get_bus_from_name(vf22_name)
            log(f"{bus11_info} and {bus12_info}")
            log(f"{bus21_info} and {bus22_info}")
            enable_dpdk_by_driverctl(vf11_mac)
            enable_dpdk_by_driverctl(vf12_mac)
            enable_dpdk_by_driverctl(vf21_mac)
            enable_dpdk_by_driverctl(vf22_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} --log-level=9 --proc-type=primary -n 4 -m 32 -- -i --print-event all --auto-start
                """
            else:
                cmd = f"""
                {testpmd} --log-level=9 --proc-type=primary -n 4 -m 32 -- -i --print-event all --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            create bonded device 1 0
            add bonding slave 0 4
            add bonding slave 2 4
            set bonding mac_addr 4 22:22:22:22:22:22
            set bonding primary 0 4
            port start 4
            set fwd txonly
            start
            stop
            port stop 4
            remove bonding slave 0 4
            set bonding primary 2 4
            add bonding slave 0 4
            port start 4
            start
            stop
            port stop 4
            remove bonding slave 2 4
            set bonding primary 0 4
            add bonding slave 2 4
            port start 4
            start
            stop
            port stop 4
            remove bonding slave 0 4
            set bonding primary 2 4
            add bonding slave 0 4
            port start 4
            start
            stop
            port stop 4
            remove bonding slave 0 4
            set bonding primary 2 4
            add bonding slave 0 4
            port start 4
            start
            stop
            port stop 4
            remove bonding slave 0 4
            set bonding primary 2 4
            add bonding slave 0 4
            port start 4
            start
            stop
            port stop 4
            remove bonding slave 0 4
            set bonding primary 2 4
            add bonding slave 0 4
            port start 4
            start
            stop
            port stop 4
            port start 4
            port stop 4
            port start 4
            port stop 4
            port start 4
            port stop 4
            port start 4
            port stop 4
            port start 4
            port stop 4
            port start 4
            port stop 4
            port start 4
            port stop 4
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            if vf_trust == True:
                m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    log("xxxxxx")
                else:
                    print(m.group())
                    log(f"yyyyy")
                pass
        with enter_phase(f"{func_name} check result"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_vf_vlan_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            #rx_vlan add all 0
            #rx_vlan add all 1
            cmd = f"""
            stop
            set verbose 9
            port stop all
            vlan set filter on 0
            vlan set filter on 1
            rx_vlan add 2 0
            rx_vlan add 2 1
            set fwd io
            vlan set strip off 0
            vlan set strip off 1
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            #write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            if vf_trust == True:
                m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Rx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Rx total result check pass")

                m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Tx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Tx total result check pass")
                pass
        with enter_phase(f"{func_name} check result"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -e ether host {nic2_mac} and vlan -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            # https://bugzilla.redhat.com/show_bug.cgi?id=2079683
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_trust == True and vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -e ether host {nic2_mac} and vlan -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_trust == True and vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass


@test_item_check
def dpdk_sriov_vf_qinq_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            vlan set filter on 1
            vlan set filter on 0
            set fwd io
            rx_vlan add 2 0
            rx_vlan add 2 1
            vlan set qinq_strip on 0
            vlan set qinq_strip on 1
            vlan set strip on 1
            vlan set strip on 0
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            #write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            if vf_trust == True:
                m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Rx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Rx total result check pass")

                m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Tx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Tx total result check pass")
                pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} ether host {nic2_mac} and vlan -e -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            # pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IP(src="1.1.1.1",dst="2.2.2.2")
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            size = 64
            # pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_trust == True and vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name}  ether host {nic2_mac} and vlan -e -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            # pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IP(src="1.1.1.1",dst="2.2.2.2")
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            size = 64
            # pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/Dot1Q(type=0x8100,vlan=4093)/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_trust == True and vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_vf_kernel_vlan_test(vf_spoofchk,vf_trust,max_tx_rate,qos):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    if max_tx_rate == 0:
        max_tx_rate_str = "-without-max-tx-rate-"
    else:
        max_tx_rate_str = "-with-max-tx-rate-"
    if qos == 0:
        qos_str = "-without-qos-"
    else:
        qos_str = "-with-qos"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str + max_tx_rate_str + qos_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_vlan_create_from_pf_mac(nic1_mac,1,2,vf_spoofchk,vf_trust,max_tx_rate,qos)
            vf2_list = vf_vlan_create_from_pf_mac(nic2_mac,1,2,vf_spoofchk,vf_trust,max_tx_rate,qos)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            #write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            if vf_trust == True:
                m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Rx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Rx total result check pass")

                m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Tx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Tx total result check pass")
                pass
        with enter_phase(f"{func_name} check result"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -e ether host {nic2_mac} and vlan -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            # https://bugzilla.redhat.com/show_bug.cgi?id=2079683
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_trust == True and vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -e ether host {nic2_mac} and vlan -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_trust == True and vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass


@test_item_check
def dpdk_sriov_vf_vlan_without_vlan_filter_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            #rx_vlan add all 0
            #rx_vlan add all 1
            cmd = f"""
            stop
            set verbose 9
            port stop all
            vlan set filter off 0
            vlan set filter off 1
            set fwd io
            vlan set strip off 0
            vlan set strip off 1
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            #write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            if vf_trust == True:
                m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Rx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Rx total result check pass")

                m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
                if None ==  m:
                    rl_fail(f"{func_name} Tx total result check failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} Tx total result check pass")
                pass
        with enter_phase(f"{func_name} check result"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -e vlan and ether host {nic2_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_trust == True and vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} -e vlan and ether host {nic2_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            #pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IP(src="1.1.1.1",dst="2.2.2.2")
            #This packet will triggered a dpdk vlan bug .
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            size = 64
            pkt = Ether()/Dot1Q(type=0x8100,vlan=2)/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_trust == True and vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_vf_mtu_test(vf_spoofchk,vf_trust,mtu_val = 1500,max_pkt_len = 9600):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_" + str(mtu_val) + "_" + str(max_pkt_len) + "_start"
    sync_end = func_name + "_" + str(mtu_val) + "_" + str(max_pkt_len) + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --mbuf={ max_pkt_len + 200 } --max-pkt-len={max_pkt_len} --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --mbuf={ max_pkt_len + 200 } --max-pkt-len={max_pkt_len} --auto-start
                """
            cmd_input = f"""
            stop
            port stop all
            port config mtu 0 {mtu_val}
            port config mtu 1 {mtu_val}
            port start all
            start
            set verbose 9
            """
            sp_obj = start_subprocess(cmd)
            write_cmd_input(sp_obj,cmd_input)
            time.sleep(5)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            out, error = sp_obj.communicate()
            if None != error:
                print(error.decode())
                rl_fail(f"{cmd} --- {cmd_input} ---failed, Please check")
            print(out.decode())
            pass
        with enter_phase(f"{func_name} clean testpmd"):
            clear_dpdk_interface_by_driverctl()
            pass
        with enter_phase(f"{func_name} check result"):
            if vf_trust == True:
                m = re.search(r'RX-total: [1-9][0-9]+',out.decode())
                if m == None:
                    rl_fail(f"{func_name} check rx-total failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} check rx-total passed")
                m = re.search(r'TX-total: [1-9][0-9]+',out.decode())
                if m == None:
                    rl_fail(f"{func_name} check tx-total failed")
                else:
                    print(m.group())
                    rl_pass(f"{func_name} check tx-total passed")
            else:
                rl_pass(f"{func_name} skip checking as trust value is false")
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu {max_pkt_len}
        ip link set {nic2_name} mtu {max_pkt_len}
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)

        sync_wait(server_target, sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = mtu_val
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt) - 4 ) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = mtu_val
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt) - 4 ) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass


@test_item_check
def dpdk_sriov_vf_broadcast_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            port start all
            start
            """
            log("Exec update testpmd command")
            log(cmd)
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
        with enter_phase(f"{func_name} check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Rx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Rx total result check pass")

            m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Tx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Tx total result check pass")
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = "FF:FF:FF:FF:FF:FF"
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = "FF:FF:FF:FF:FF:FF"
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_vf_multicast_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            port start all
            mcast_addr add 0 01:00:5e:f8:f8:f8
            mcast_addr add 1 01:00:5e:f8:f8:f8
            mcast_addr add 0 33:33:f8:f8:f8:f8
            mcast_addr add 1 33:33:f8:f8:f8:f8
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop runtime"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
            m = re.search(r"RX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Rx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Rx total result check pass")

            m = re.search(r"TX-total: [1-9][0-9]+",out.decode())
            if None ==  m:
                rl_fail(f"{func_name} Tx total result check failed")
            else:
                print(m.group())
                rl_pass(f"{func_name} Tx total result check pass")
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = "01:00:5e:f8:f8:f8"
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            pkt.dst= "33:33:f8:f8:f8:f8"
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = "01:00:5e:f8:f8:f8"
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            pkt.dst= "33:33:f8:f8:f8:f8"
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#Bug2101710
#Steps to Reproduce:
#1) Set VF in trust
#2) Run DPDK testpmd with one VF
#3) Inside testpmd, run “>set promisc 0 off” (turn promiscuous mode of port #0 off)
#4) Send traffic with untagged packets, single VLAN and double VLAN packets with destination addresses that match the VF MAC address.
#5) For correct behavior, VF is expected to receive all the traffic (untagged packets and tagged packets).
#BUG https://bugzilla.redhat.com/show_bug.cgi?id=2166909 [Mellanox][CX6][RHEL9.2] dpdk sriov vf promisc does not work
@test_item_check
def dpdk_sriov_vf_promisc_bug2101710_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase("topo init"):
            init_physical_topo_with_one_pair_ports()
            import time
            time.sleep(60)
            sync_set(client_target,"init_physical_topo_with_one_pair_ports_Done")
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            cmd = f"""
            ip li set {nic1_name} up
            ip li set {nic2_name} up
            sleep 30
            """
            run(cmd)
            nic1_carrier = bash(f"cat /sys/class/net/{nic1_name}/carrier").value()
            nic2_carrier = bash(f"cat /sys/class/net/{nic2_name}/carrier").value()
            if int(nic1_carrier) == 1:
                vf_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            elif int(nic2_carrier) == 1:
                vf_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            else:
                rl_fail(f"Both {nic1_name} and {nic2_name} are not up now")
            clear_dpdk_interface_by_driverctl()
            log(vf_list)
            vf_name = vf_list[0]
            log(f"{vf_name} and {vf_name}")
            vf_mac = pysriov.sriov_get_mac_from_name(vf_name)
            log(f"{vf_mac} and {vf_mac}")
            bus_info = my_tool.get_bus_from_name(vf_name)
            log(f"{bus_info} and {bus_info}")
            enable_dpdk_by_driverctl(vf_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus_info}  -- -i --forward-mode=macswap --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus_info}  -- -i --forward-mode=macswap --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            set promisc all off
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            cmd = f"""
            echo "{vf_mac}" | nc -l -p 8888
            """
            run(cmd)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
        with enter_phase("topo restore"):
            init_physical_topo_without_switch()
            import time
            time.sleep(30)
            sync_set(client_target,"restore_topo_with_two_pair_ports_Done")
    elif i_am_client():
        sync_wait(server_target,"init_physical_topo_with_one_pair_ports_Done")
        sync_wait(server_target,sync_start)
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        sleep 30
        """
        run(cmd)
        nic1_carrier = bash(f"cat /sys/class/net/{nic1_name}/carrier").value()
        nic2_carrier = bash(f"cat /sys/class/net/{nic2_name}/carrier").value()
        if int(nic1_carrier) == 1:
            nic_name = nic1_name
            nic_mac = nic1_mac
        elif int(nic2_carrier) == 1:
            nic_name = nic2_name
            nic_mac = nic2_mac
        else:
            rl_fail(f"Both {nic1_name} and {nic2_name} are not up now")

        #get server side mac address
        server_name = os.environ["SERVERS"]
        cmd = f"""
        wget http://{server_name}:8888 -O /tmp/server_vf_mac
        ls -al /tmp/
        """
        run(cmd)

        if os.path.exists("/tmp/server_vf_mac"):
            server_vf_mac = bash("cat /tmp/server_vf_mac").value()
        else:
            rl_fail("get server side vf mac failed")
            server_vf_mac = ""

        ###############################################
        ###############################################
        ###############################################
        with enter_phase(f"{func_name} IPV4 packets check"):
            log("normal packets send and receive test")
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic_name} ether host {server_vf_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            log("send 10 normal packets")
            size = 64
            pkt = Ether(dst=server_vf_mac)/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.src = nic_mac
            pkt.dst = server_vf_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic_name)
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 3
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'check normal receive pkts' '$pkt_num' '{send_pkt_num * 2}'
            """
            print(cmd)
            run(cmd)

            ###############################################
            ###############################################
            ###############################################
            log("VLAN packets send and receive test")
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic_name} ether host {server_vf_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            log("send 10 vlan packets")
            size = 64
            pkt = Ether(dst=server_vf_mac)/Dot1Q(vlan=10)/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = server_vf_mac
            pkt.src = nic_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic_name)
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 3
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'VLAN packets send and receive test' '$pkt_num' '{send_pkt_num * 2}'
            """
            print(cmd)
            run(cmd)

            ###############################################
            ###############################################
            ###############################################
            log("QINQ packets send and receive test")
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic_name} ether host {server_vf_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            log("send 10 QINQ packets")
            size = 64
            pkt = Ether(dst=server_vf_mac)/Dot1Q(vlan=20)/Dot1Q(vlan=10)/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = server_vf_mac
            pkt.src = nic_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic_name)
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 3
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'QINQ packets send and receive test' '$pkt_num' '{send_pkt_num * 2}'
            """
            print(cmd)
            run(cmd)
        ###############################################
        ###############################################
        ###############################################
        with enter_phase(f"{func_name} IPV6 packets check"):
            log("normal packets send and receive test")
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic_name} ether host {server_vf_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            log("send 10 normal packets")
            size = 64
            pkt = Ether(dst=server_vf_mac)/IPv6(src="3000::100",dst="3000::200")
            pkt.src = nic_mac
            pkt.dst = server_vf_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic_name)
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 3
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'check ipv6 normal receive pkts' '$pkt_num' '{send_pkt_num * 2}'
            """
            print(cmd)
            run(cmd)

            ###############################################
            ###############################################
            ###############################################
            log("VLAN packets send and receive test")
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic_name} ether host {server_vf_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            log("send 10 vlan packets")
            size = 64
            pkt = Ether(dst=server_vf_mac)/Dot1Q(vlan=10)/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = server_vf_mac
            pkt.src = nic_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic_name)
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 3
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'check vlan ipv6 packets send and receive test' '$pkt_num' '{send_pkt_num * 2}'
            """
            print(cmd)
            run(cmd)

            ###############################################
            ###############################################
            ###############################################
            log("QINQ packets send and receive test")
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic_name} ether host {server_vf_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            from scapy.layers.l2 import Dot1Q
            log("send 10 QINQ packets")
            size = 64
            pkt = Ether(dst=server_vf_mac)/Dot1Q(vlan=20)/Dot1Q(vlan=10)/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = server_vf_mac
            pkt.src = nic_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic_name)
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 3
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'QINQ ipv6 packets send and receive test' '$pkt_num' '{send_pkt_num * 2}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        sync_wait(server_target,"restore_topo_with_two_pair_ports_Done")
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_vf_macaddress_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    vf_mac = "00:11:22:33:44:1A"
    import ethtool
    driver_name = ethtool.get_module(nic1_name)
    if i_am_server():
        with enter_phase("topo init"):
            init_physical_topo_with_one_pair_ports()
            import time
            time.sleep(60)
            sync_set(client_target,"init_physical_topo_with_one_pair_ports_Done")
        with enter_phase(f"{func_name}"):
            if driver_name == "mlx5_core":
                mlx_driver_flag = True
            else:
                mlx_driver_flag = False

            clear_dpdk_interface_by_driverctl()
            cmd = f"""
            ip li set {nic1_name} up
            ip li set {nic2_name} up
            sleep 30
            """
            run(cmd)
            nic1_carrier = bash(f"cat /sys/class/net/{nic1_name}/carrier").value()
            nic2_carrier = bash(f"cat /sys/class/net/{nic2_name}/carrier").value()
            if int(nic1_carrier) == 1:
                vf_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
                nic_test = nic1_name
            elif int(nic2_carrier) == 1:
                vf_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
                nic_test = nic2_name
            else:
                rl_fail(f"Both {nic1_name} and {nic2_name} are not up now")
            clear_dpdk_interface_by_driverctl()
            log(vf_list)
            vf_name = vf_list[0]
            log(f"{vf_name} and {vf_name}")
            cmd = f"""
            ip link set {nic_test} vf 0 mac {vf_mac}
            """
            run(cmd)
            log(f"{vf_mac} and {vf_mac}")
            bus_info = my_tool.get_bus_from_name(vf_name)
            log(f"{bus_info} and {bus_info}")
            #enable_dpdk_by_driverctl(vf_mac)
            enable_dpdk_by_driverctl_with_pci_addr(bus_info,mlx_driver_flag)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus_info}  -- -i --forward-mode=macswap --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus_info}  -- -i --forward-mode=macswap --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            cmd = f"""
            echo "{vf_mac}" | nc -l -p 8888
            """
            #run(cmd)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
        with enter_phase("topo restore"):
            init_physical_topo_without_switch()
            import time
            time.sleep(30)
            sync_set(client_target,"restore_topo_with_two_pair_ports_Done")
    elif i_am_client():
        sync_wait(server_target,"init_physical_topo_with_one_pair_ports_Done")
        sync_wait(server_target,sync_start)
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        sleep 30
        """
        run(cmd)
        nic1_carrier = bash(f"cat /sys/class/net/{nic1_name}/carrier").value()
        nic2_carrier = bash(f"cat /sys/class/net/{nic2_name}/carrier").value()
        if int(nic1_carrier) == 1:
            nic_name = nic1_name
            nic_mac = nic1_mac
        elif int(nic2_carrier) == 1:
            nic_name = nic2_name
            nic_mac = nic2_mac
        else:
            rl_fail(f"Both {nic1_name} and {nic2_name} are not up now")

        server_vf_mac = vf_mac

        ###############################################
        ###############################################
        ###############################################
        with enter_phase(f"{func_name} IPV4 packets check"):
            log("normal packets send and receive test")
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic_name} ether host {server_vf_mac} -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10
            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            from scapy.layers.l2 import Dot1Q
            log("send 10 normal packets")
            size = 64
            pkt = Ether(dst=server_vf_mac)/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.src = nic_mac
            pkt.dst = server_vf_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic_name)
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 3
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q   | wc -l`
            rlAssertEquals 'check normal receive pkts' '$pkt_num' '{send_pkt_num * 2}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        sync_wait(server_target,"restore_topo_with_two_pair_ports_Done")
        pass
    else:
        pass


#E810-XXV - Multicast packets are not received by all VFs on the same port even though they have the same VLAN
@test_item_check
def dpdk_sriov_vf_bug2088787_test(vf_spoofchk,vf_trust):
    func_name = inspect.stack()[0][3] + str(vf_spoofchk) + str(vf_trust)
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    sync_topo_init = func_name + "_topo_init_one_pair_ports"
    sync_topo_restore = func_name + "_restore_topo_with_two_pair_ports"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    major_ver = int(os.environ.get("X_VERSION"))
    if i_am_server():
        with enter_phase(f"{func_name}_topo_init"):
            init_physical_topo_with_one_pair_ports()
            import time
            time.sleep(30)
            sync_set(client_target,sync_topo_init)
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            cmd = f"""
            ip li set {nic1_name} up
            ip li set {nic2_name} up
            sleep 30
            """
            run(cmd)

            cmd = f"""
            podman kill -a
            podman rm -a
            podman rmi -a
            """
            run(cmd)

            nic1_carrier = bash(f"cat /sys/class/net/{nic1_name}/carrier").value()
            nic2_carrier = bash(f"cat /sys/class/net/{nic2_name}/carrier").value()
            if int(nic1_carrier) == 1:
                nic_name = nic1_name
                nic_mac = nic1_mac
            elif int(nic2_carrier) == 1:
                nic_name = nic2_name
                nic_mac = nic2_mac
            else:
                rl_fail(f"Both {nic1_name} and {nic2_name} are not up now")

            cmd = f"""
            ethtool --set-priv-flags {nic_name} vf-true-promisc-support off
            ethtool --show-priv-flags {nic_name}
            """
            run(cmd,"0,1")

            vf_list = vf_create_from_pf_mac(nic_mac,2,vf_spoofchk,vf_trust)
            clear_dpdk_interface_by_driverctl()
            log(vf_list)
            vf1_name = vf_list[0]
            vf2_name = vf_list[1]
            log(f"vf1_name and {vf1_name}")
            log(f"vf2_name and {vf2_name}")

            cmd = f"""
            ip link set {nic_name} vf 0 spoofchk off trust on
            ip link set {nic_name} vf 1 spoofchk off trust on
            sleep 5
            """
            run(cmd)

            cmd = f"""
            ip li set {nic_name} vf 0 vlan 520
            ip li set {nic_name} vf 1 vlan 520
            sleep 5

            ip link set {vf1_name} allmulticast on
            ip link set {vf2_name} allmulticast on
            sleep 5

            podman pod create -n p1
            podman pod create -n p2

            podman pod start p1
            podman pod start p2

            podman run -it -d --privileged --name p1-con --pod p1 registry.access.redhat.com/ubi{major_ver}
            podman run -it -d --privileged --name p2-con --pod p2 registry.access.redhat.com/ubi{major_ver}
            podman ps -a --pod

            podman exec -it p1-con bash -c "dnf -y install iproute iputils wget"
            podman exec -it p2-con bash -c "dnf -y install iproute iputils wget"
            """
            run(cmd)

            mnt_p1_con = bash("podman mount p1-con").value()
            cmd = f"""
            cp -R /etc/yum.repos.d/beaker-BaseOS.repo {mnt_p1_con}/etc/yum.repos.d/
            cp -R /etc/yum.repos.d/beaker-AppStream.repo {mnt_p1_con}/etc/yum.repos.d/
            podman umount p1-con
            """
            run(cmd)

            mnt_p2_con = bash("podman mount p2-con").value()
            cmd = f"""
            cp -R /etc/yum.repos.d/beaker-BaseOS.repo {mnt_p2_con}/etc/yum.repos.d/
            cp -R /etc/yum.repos.d/beaker-AppStream.repo {mnt_p2_con}/etc/yum.repos.d/
            podman umount p2-con
            """
            run(cmd)

            cmd = f"""
            podman exec -it p1-con bash -c "ls -al /etc/yum.repos.d/"
            podman exec -it p2-con bash -c "ls -al /etc/yum.repos.d/"

            podman exec -it p1-con bash -c "dnf -y install tcpdump numactl-libs"
            podman exec -it p2-con bash -c "dnf -y install tcpdump numactl-libs"
            """
            run(cmd)

            p1_con_id=bash("podman inspect -f '{{.State.Pid}}' p1-con").value()
            p2_con_id=bash("podman inspect -f '{{.State.Pid}}' p2-con").value()
            cmd = f"""
            rm -f /var/run/netns/{p1_con_id}
            rm -f /var/run/netns/{p2_con_id}

            ln -s /proc/{p1_con_id}/ns/net /var/run/netns/{p1_con_id}
            ln -s /proc/{p2_con_id}/ns/net /var/run/netns/{p2_con_id}
            ls -al /var/run/netns

            ip link set {vf1_name} netns {p1_con_id}
            ip link set {vf2_name} netns {p2_con_id}

            podman exec -it p1-con ip ad flush {vf1_name}
            podman exec -it p2-con ip ad flush {vf2_name}

            #set address
            podman exec -it p1-con bash -c "ip li set {vf1_name} up"
            podman exec -it p1-con bash -c "ip addr add 2001:1b74:480:6076:9000::ff00/64 dev {vf1_name}"
            podman exec -it p1-con bash -c "ip ad show"
            podman exec -it p1-con bash -c "ip li show"

            podman exec -it p2-con bash -c "ip li set {vf2_name} up"
            podman exec -it p2-con bash -c "ip addr add 2001:1b74:480:6074:9000::ff01/64 dev {vf2_name}"
            podman exec -it p2-con bash -c "ip ad show"
            podman exec -it p2-con bash -c "ip li show"
            """
            run(cmd)

            #start two bash
            pkt1_file_name = "p1-con.cap"
            pkt2_file_name = "p2-con.cap"
            log("start new process for p1-con tcpdump")
            cmd = f"""
            podman exec -it p1-con bash -c "tcpdump -ne -i {vf1_name} ether host 33:33:f8:f8:f8:f8 -w {pkt1_file_name}"
            """
            obj1 = start_subprocess(cmd,3)

            log("start new process for p2-con tcpdump")
            cmd = f"""
            podman exec -it p2-con bash -c "tcpdump -ne -i {vf2_name} ether host 33:33:f8:f8:f8:f8 -w {pkt2_file_name}"
            """
            obj2 = start_subprocess(cmd,3)

            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)

        with enter_phase(f"{func_name} stop and check result"):
            cmd = f"""
            sleep 3
            podman exec -it p1-con bash -c "killall tcpdump"
            sleep 3
            kill -9 {obj1.pid}
            """
            run(cmd)
            out1,error1 = obj1.communicate()
            if None != error1:
                log(out1.decode())
                rl_fail(f"{func_name} {error1} {error1.decode()}")

            cmd = f"""
            sleep 3
            podman exec -it p2-con bash -c "killall tcpdump"
            sleep 3
            kill -9 {obj2.pid}
            """
            run(cmd)
            out2,error2 = obj2.communicate()
            if None != error2:
                log(out2.decode())
                rl_fail(f"{func_name} {error2} {error2.decode()}")
            run("sleep 3")

            cmd = f"""
            podman cp p1-con:/{pkt1_file_name} {case_path}/
            podman cp p2-con:/{pkt2_file_name} {case_path}/
            """
            run(cmd)

            send_pkt_num = 10
            cmd = f"""
            pushd {case_path}
            unset pkt_num
            pkt_num=`tcpdump -r {pkt1_file_name} -q   | wc -l`
            rlAssertGreaterOrEqual 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            popd
            """
            print(cmd)
            run(cmd)

            cmd = f"""
            pushd {case_path}
            unset pkt_num
            pkt_num=`tcpdump -r {pkt2_file_name} -q   | wc -l`
            rlAssertGreaterOrEqual 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            popd
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} clear container env"):
            clear_container_env()
            clear_dpdk_interface_by_devbind()
            clear_dpdk_interface_by_driverctl()
            clear_env()
        with enter_phase("topo restore"):
            init_physical_topo_without_switch()
            run("sleep 60")
            sync_set(client_target,sync_topo_restore)
    elif i_am_client():
        sync_wait(server_target,sync_topo_init)
        sync_wait(server_target,sync_start)
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        sleep 30
        """
        run(cmd)
        nic1_carrier = bash(f"cat /sys/class/net/{nic1_name}/carrier").value()
        nic2_carrier = bash(f"cat /sys/class/net/{nic2_name}/carrier").value()
        if int(nic1_carrier) == 1:
            nic_name = nic1_name
            nic_mac = nic1_mac
        elif int(nic2_carrier) == 1:
            nic_name = nic2_name
            nic_mac = nic2_mac
        else:
            rl_fail(f"Both {nic1_name} and {nic2_name} are not up now")

        ###############################################
        ###############################################
        ###############################################
        log("send packets test")
        send_pkt_num = 10
        from scapy import all
        from scapy.layers.l2 import Ether
        from scapy.utils import hexdump
        from scapy.sendrecv import sendp
        from scapy.layers.inet import IP
        from scapy.layers.inet6 import IPv6
        from scapy.layers.l2 import Dot1Q
        size = 64
        pkt = Ether()/Dot1Q(type=0x8100,vlan=520)/IPv6(dst="ff02::1")
        pkt.dst= "33:33:f8:f8:f8:f8"
        payload = max(0, size - len(pkt)) * 'X'
        pkt.add_payload(payload.encode())
        pkt.show()
        sendp(pkt,count=send_pkt_num,inter=1,iface=nic_name)
        import time
        time.sleep(3)
        sync_set(server_target,sync_end)
        clear_env()
        sync_wait(server_target,sync_topo_restore)
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_vf_promisc_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            enable_dpdk_by_driverctl(vf1_mac)
            enable_dpdk_by_driverctl(vf2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            set promisc all on
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

def guest_start_testpmd(guest_name):
    #testpmd=$(grep COMPILE_DPDK_TESTPMD /root/all_guest_cmd | awk -F '=' '{{print $NF}}')
    testpmd =  get_testpmd()
    if dpdk_verion > 20:
        cmd = fr"""
        {testpmd} -l 0,1,2 -a 0000:03:00.0 -a 0000:04:00.0 -- -i --auto-start
        """
    else:
        cmd = fr"""
        {testpmd} -l 0,1,2 -w 0000:03:00.0 -w 0000:04:00.0 -- -i --auto-start
        """
    pts = bash(f"virsh ttyconsole {guest_name}").value()
    all_result = my_tool.run_cmd_get_output(pts, cmd,"testpmd>")
    log(all_result)
    pass


def check_guest_testpmd_result(guest_name):
    cmd = f"""
    show port info all
    show port stats all
    """
    pts = bash(f"virsh ttyconsole {guest_name}").value()
    ret = my_tool.run_cmd_get_output(pts, cmd,"testpmd>")
    log(ret)
    return 0

def get_guest_nic_name_from_bus(guest_name,bus_info):
    cmd = f"""
    ls /sys/bus/pci/devices/{bus_info}/net/
    """
    pts = bash(f"virsh ttyconsole {guest_name}").value()
    ret = my_tool.run_cmd_get_output(pts, cmd)
    log(ret)
    return ret

#bond_mode : only active-backup is supported by now .
def vm_create_linux_bond_with_vlan_sub_int(guest_name,nic1_pci,nic2_pci,bond_mode,vlan_id):
    cmd = f"""
    set -x
    modprobe -r bonding
    eth1_name=$(ls /sys/bus/pci/devices/{nic1_pci}/net/)
    eth2_name=$(ls /sys/bus/pci/devices/{nic2_pci}/net/)
    ip link add bond0 type bond
    ip link set bond0 type bond miimon 100 mode {bond_mode}
    ip link set $eth1_name down
    ip link set $eth1_name master bond0
    ip link set $eth2_name down
    ip link set $eth2_name master bond0
    ip link set bond0 up
    ip link add link bond0 name bond0.{vlan_id} type vlan id {vlan_id}
    ip link set bond0.{vlan_id} up
    ip addr add 192.168.99.100/24 dev bond0.{vlan_id}
    ip -d link show
    ip -d addr show
    set +x
    """
    pts = bash(f"virsh ttyconsole {guest_name}").value()
    ret = my_tool.run_cmd_get_output(pts, cmd)
    log(ret)
    return 0

@test_item_check
def dpdK_sriov_vf_in_guest_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            # enable_dpdk_by_driverctl(vf1_mac)
            # enable_dpdk_by_driverctl(vf2_mac)
            with pushd(case_path):
                xml_file = "g1.xml"
                cmd = f"""
                rm -f {xml_file}
                cp guest.xml {xml_file}
                """
                run(cmd)

                dir_prefix,guest_name = create_image_file(xml_file)

                guest_image_path = dir_prefix + "/" + guest_name + ".qcow2"

                xml_tool.update_image_source(xml_file, guest_image_path)

                update_guest_image_net_rules(guest_image_path)

                update_guest_xml_cpu(xml_file)

                customize_guest(guest_name)

                install_dpdk_inside_guest(guest_image_path)

                start_and_dumpxml_guest(guest_name)

                update_guest_isolate_cpus(guest_name)

                attach_sriov_vf_to_vm(xml_file,guest_name,vf1_name,vf2_name)

                vm_install_dpdk(guest_name)

                guest_start_testpmd(guest_name)

            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} clear dpdk interface"):
            destroy_guest(guest_name)
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            if vf_spoofchk == False and vf_trust == True:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
                """
                print(cmd)
                run(cmd)
                pass
            else:
                cmd = f"""
                sleep 2
                pkill tcpdump
                sleep 2
                unset pkt_num
                pkt_num=`tcpdump -r abc.cap -q   | wc -l`
                rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '0'
                """
                print(cmd)
                run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdK_sriov_vf_in_guest_bug2143985_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    import ethtool
    driver_name = ethtool.get_module(nic1_name)
    if driver_name == "mlx5_core":
        mlx_driver_flag = True
    else:
        mlx_driver_flag = False

    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            with pushd(case_path):
                xml_file = "g1.xml"
                cmd = f"""
                rm -f {xml_file}
                cp guest.xml {xml_file}
                """
                run(cmd)

                dir_prefix,guest_name = create_image_file(xml_file)

                guest_image_path = dir_prefix + "/" + guest_name + ".qcow2"

                xml_tool.update_image_source(xml_file, guest_image_path)

                update_guest_image_net_rules(guest_image_path)

                update_guest_xml_cpu(xml_file)

                customize_guest(guest_name)

                install_dpdk_inside_guest(guest_image_path)

                start_and_dumpxml_guest(guest_name)

                update_guest_isolate_cpus(guest_name)

                attach_sriov_vf_to_vm(xml_file,guest_name,vf1_name,vf2_name)

                vm_create_linux_bond_with_vlan_sub_int(guest_name,"0000:03:00.0","0000:04:00.0","active-backup",3)

                #bind the vf nic to vfio-pci userspace driver.
                enable_dpdk_by_driverctl_with_pci_addr(bus1_info,mlx_driver_flag)
                enable_dpdk_by_driverctl_with_pci_addr(bus2_info,mlx_driver_flag)

            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} clear dpdk interface"):
            destroy_guest(guest_name)
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        sync_wait(server_target,sync_start)
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        ip link add link {nic1_name} name {nic1_name}.3 type vlan id 3
        ip link set {nic1_name}.3 up
        ip link add link {nic2_name} name {nic2_name}.3 type vlan id 3
        ip link set {nic2_name}.3 up
        ip addr add 192.168.99.99/24 dev {nic1_name}.3
        ip -d link show
        ip -d addr show
        """
        run(cmd)
        obj1 = bash("ping 192.168.99.100 -c 20")
        log(obj1.stdout)
        log(obj1.stderr)
        if obj1.code != 0:
            cmd = f"""
            ip ad flush {nic1_name}.3
            ip ad flush {nic2_name}.3
            ip ad ad 192.168.99.99/24 dev {nic2_name}.3
            ip link set {nic2_name}.3 up
            ip ad show
            """
            run(cmd)
            obj2 = bash("ping 192.168.99.100 -c 20")
            log(obj2.stdout)
            log(obj2.stderr)
        if obj1.code != 0 and obj2.code != 0:
            rl_fail("ping 192.168.99.100 -c 20 FAILED")
        else:
            rl_pass("ping 192.168.99.100 -c 20 PASSED")
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#only enable for mellanox now
# [,baifә'keiʃәn] test
@test_item_check
def dpdk_flow_bifurcation_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            flow isolate 0 true
            flow isolate 1 true
            port start all
            flow create 0 ingress pattern eth / ipv4 / end actions rss queues 0 end  / end
            flow create 1 ingress pattern eth / ipv4 / end actions rss queues 0 end  / end
            flow create 0 ingress pattern eth / ipv6 / end actions rss queues 0 end  / end
            flow create 1 ingress pattern eth / ipv6 / end actions rss queues 0 end  / end
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#https://doc.dpdk.org/dts/test_plans/qos_api_test_plan.html
#Data Center Bridging (DCB)
#only for ixgbe and i40e
# testpmd> port config 1 dcb vt off 4 pfc off
# testpmd> port config 0 dcb vt off 4 pfc off
# net_mlx5: port 0 cannot handle this many Rx queues (1024)
# Port0 dev_configure = -22
# Cannot initialize network ports.
# testpmd>             port config 0 dcb vt off 4 pfc off
# testpmd>             port config 1 dcb vt off 4 pfc off
# Done
# net_mlx5: port 1 cannot handle this many Rx queues (1024)
# Port1 dev_configure = -22
# testpmd>             port start all
# Cannot initialize network ports.
# Configuring Port 0 (socket 0)
# net_mlx5: port 0 cannot handle this many Rx queues (1024)
# Port0 dev_configure = -22
# testpmd>             start
# testpmd>             stopFail to configure port 0
@test_item_check
def dpdk_qos_nic_partition_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -a {bus1_info} -a {bus2_info} -- -i --nb-cores=4 --rxq=4 --txq=4
                """
            else:
                cmd = f"""
                {testpmd} -w {bus1_info} -w {bus2_info} -- -i --nb-cores=4 --rxq=4 --txq=4
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            set verbose 9
            port stop all
            port config 0 dcb vt off 4 pfc off
            port config 1 dcb vt off 4 pfc off
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            run("sleep 3")
        with enter_phase(f"{func_name} stop and check result"):
            write_cmd_input(sp_obj,"stop")
            out,error = sp_obj.communicate()
            if None != error:
                print(f"{func_name} start testpmd failed")
                print(error.decode())
            print(out.decode())
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

#Wtih binary_search version
def dpdk_standalone_throughput_test_with_trex(t_time,pkt_size):
    trex_host = os.getenv("TREX_SERVER_IP")
    trex_server_ip = socket.gethostbyname(trex_host)
    trex_url = os.getenv("TREX_URL")
    trex_dir = os.path.basename(trex_url).replace(".tar.gz","")
    trex_name = os.path.basename(trex_url)
    #init trex package and lua traffic generator
    # [ -e trafficgen ] || git clone https://github.com/atheurer/trafficgen.git
    # [ -e trafficgen ] || git clone https://github.com/wanghekai/trafficgen.git
    with pushd("/opt"):
        if not os.path.exists("/opt/trafficgen"):
            git_clone_url("https://github.com/atheurer/trafficgen.git")
            pass
    with pushd("/opt"):
        cmd = fr"""
        mkdir -p trex
        pushd trex &>/dev/null
        [ -f {trex_name} ] || wget -nv -N {trex_url};tar xf {trex_name};ln -sf {trex_dir} current; ls -l;
        popd &>/dev/null
        chmod 777 /opt/trex -R
        """
        log_and_run(cmd)
        pass
    with pushd(case_path):
        ret = bash(f"ping {trex_server_ip} -c 3")
        if ret.code != 0:
            log("Trex server {} not up please check ".format(trex_server_ip))
        pass

    with pushd("/opt/trafficgen"):
        cmd = f"""
        python3 ./binary-search.py \
        --trex-host={trex_server_ip} \
        --traffic-generator=trex-txrx \
        --frame-size={pkt_size} \
        --traffic-direction=bidirectional \
        --search-runtime={t_time} \
        --runtime-tolerance=10 \
        --search-granularity=0.5 \
        --validation-runtime=10 \
        --negative-packet-loss=fail \
        --max-loss-pct=0.0 \
        --rate-unit=% \
        --rate=100
        """
        log(cmd)
        py3_run(cmd)
    return 0

#this covered by vsperf and testpmd as switch project
@test_item_check
def dpdk_testpmd_l2_performance_test(burst_num):
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    bus2_info = my_tool.get_bus_from_name(nic2_name)
    testpmd = get_testpmd()
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            enable_dpdk_by_driverctl(nic1_mac)
            enable_dpdk_by_driverctl(nic2_mac)
            numa_node = os.environ.get("SERVER_NUMA")
            vcpu_num = 4
            all_vcpus = my_tool.get_isolate_cpus_on_numa(numa_node)
            vcpus = all_vcpus.split(" ")[0:vcpu_num]
            log(f"vm1 numa node is {numa_node} vcpu num is {vcpu_num} vcpus {vcpus}")
            if dpdk_verion > 20:
                cmd = f"""
                {testpmd} -l {vcpus[0]},{vcpus[1]},{vcpus[2]} -a {bus1_info} -a {bus2_info} -- -i --auto-start
                """
            else:
                cmd = f"""
                {testpmd} -l {vcpus[0]},{vcpus[1]},{vcpus[2]} -w {bus1_info} -w {bus2_info} -- -i --auto-start
                """
            sp_obj = start_subprocess(cmd)
            cmd = f"""
            stop
            port stop all
            show config rxtx
            port config all burst {burst_num}
            show config rxtx
            port start all
            start
            """
            log("Exec update testpmd command")
            write_cmd_input(sp_obj,cmd)
            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
        with enter_phase(f"{func_name} stop and check result"):
            dpdk_standalone_throughput_test_with_trex(30,64)
            time.sleep(3)
            out,error = sp_obj.communicate(b"stop")
            if None != error:
                print(f"{func_name} start testpmd runtime failed.")
                print(error.decode())
            print(out.decode())
            sync_wait(client_target,"dpdk_testpmd_l2_performance_test_performance_test")
            pass
        with enter_phase(f"{func_name} clear dpdk interface"):
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        cmd = f"""
        killall t-rex-64
        killall _t-rex-64
        """
        run(cmd,"0,1")
        sync_wait(server_target,sync_start)
        trex_url = os.getenv("TREX_URL")
        install_trex_and_start(nic1_mac,nic2_mac,trex_url)
        sync_set(server_target,sync_end)
        sync_set(server_target,"dpdk_testpmd_l2_performance_test_performance_test")
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_testpmd_in_guest_performance_test(vf_spoofchk,vf_trust):
    clear_env()
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    if i_am_server():
        with enter_phase(f"{func_name}"):
            clear_dpdk_interface_by_driverctl()
            vf1_list = vf_create_from_pf_mac(nic1_mac,1,vf_spoofchk,vf_trust)
            vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
            log(f"{vf1_list} and  {vf2_list}")
            vf1_name = vf1_list[0]
            vf2_name = vf2_list[0]
            log(f"{vf1_name} and {vf2_name}")
            vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
            vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
            log(f"{vf1_mac} and {vf2_mac}")
            bus1_info = my_tool.get_bus_from_name(vf1_name)
            bus2_info = my_tool.get_bus_from_name(vf2_name)
            log(f"{bus1_info} and {bus2_info}")
            # enable_dpdk_by_driverctl(vf1_mac)
            # enable_dpdk_by_driverctl(vf2_mac)
            with pushd(case_path):
                xml_file = "g1.xml"
                cmd = f"""
                rm -f {xml_file}
                cp guest.xml {xml_file}
                """
                run(cmd)

                dir_prefix,guest_name = create_image_file(xml_file)

                guest_image_path = dir_prefix + "/" + guest_name + ".qcow2"

                xml_tool.update_image_source(xml_file, guest_image_path)

                update_guest_image_net_rules(guest_image_path)

                update_guest_xml_cpu(xml_file)

                customize_guest(guest_name)

                install_dpdk_inside_guest(guest_image_path)

                start_and_dumpxml_guest(guest_name)

                update_guest_isolate_cpus(guest_name)

                attach_sriov_vf_to_vm(xml_file,guest_name,vf1_name,vf2_name)

                vm_install_dpdk(guest_name)

                guest_start_testpmd(guest_name)

            sync_set(client_target, sync_start)
            sync_wait(client_target,sync_end)
            dpdk_standalone_throughput_test_with_trex(10,64)
            sync_wait(client_target,"dpdk_sriov_testpmd_in_guest_performance_test")
            run("sleep 3")
        with enter_phase(f"{func_name} clear dpdk interface"):
            check_guest_testpmd_result(guest_name)
            destroy_guest(guest_name)
            clear_dpdk_interface_by_driverctl()
            pass
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        cmd = f"""
        killall t-rex-64
        killall _t-rex-64
        """
        run(cmd,"0,1")
        sync_wait(server_target,sync_start)
        trex_url = os.getenv("TREX_URL")
        install_trex_and_start(nic1_mac,nic2_mac,trex_url)
        sync_set(server_target,sync_end)
        sync_set(server_target,"dpdk_sriov_testpmd_in_guest_performance_test")
        pass
    else:
        pass

@test_item_check
def dpdk_testpmd_in_container_test():
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    clear_container_env()
    clear_dpdk_interface_by_devbind()
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    nic1_bus = my_tool.get_bus_from_name(nic1_name)
    nic2_bus = my_tool.get_bus_from_name(nic2_name)
    nic_dirver = my_tool.get_nic_driver_from_name(nic1_name)
    if i_am_server():
        if system_version_id >= 90:
            image_name = "rhel9-dpdk"
        elif system_version_id >= 80:
            image_name = "rhel8-dpdk21"
        else:
            run("echo 'not support now'")
        cmd = f"""
        podman login -u="wanghekai" -p="gc1UHQzSLlK4zizr3eggM9U5yw9uTUPPYmHgn0uqsG3aEZ/DJQQwFf3XQYC0HBwI" quay.io
        podman pull quay.io/wanghekai/{image_name}
        """
        run(cmd)

        cmd = f"""
        podman run -it -d --privileged \
        --name my-rhel-dpdk \
        -v /sys/bus/pci/drivers:/sys/bus/pci/drivers \
        -v /sys/kernel/mm/hugepages:/sys/kernel/mm/hugepages \
        -v /sys/devices/system/node:/sys/devices/system/node \
        -v /dev:/dev \
        -v /lib:/lib \
        quay.io/wanghekai/{image_name}
        """
        run(cmd)

        container_pid = bash("podman inspect -f '{{.State.Pid}}' my-rhel-dpdk")
        cmd = f"""
        rm -f /var/run/netns/{container_pid}
        ls -al  /proc/{container_pid}/ns/net
        ln -s /proc/{container_pid}/ns/net /var/run/netns/{container_pid}
        ls -al /var/run/netns
        """
        run(cmd)

        cmd = f"""
        ip li set {nic1_name} netns {container_pid}
        ip li set {nic2_name} netns {container_pid}
        """
        run(cmd)

        cmd = f"""
        podman exec my-rhel-dpdk bash -c "killall dpdk-testpmd"
        podman exec my-rhel-dpdk bash -c "killall dpdk-testpmd"
        podman exec my-rhel-dpdk bash -c "killall dpdk-testpmd"
        """
        run(cmd,"0,1")

        if "mlx" in nic_dirver:
            cmd = f"""
            podman exec my-rhel-dpdk bash -c "dnf install -y ethtool"
            podman exec my-rhel-dpdk bash -c "dnf install -y procps-ng"
            podman exec my-rhel-dpdk bash -c "ip -d link show"
            """
            run(cmd)
        else:
            cmd = f"""
            podman exec my-rhel-dpdk bash -c "dnf install -y ethtool"
            podman exec my-rhel-dpdk bash -c "dnf install -y procps-ng"
            podman exec my-rhel-dpdk bash -c "ip -d link show"
            podman exec -it my-rhel-dpdk bash -c "modprobe vfio"
            podman exec -it my-rhel-dpdk bash -c "modprobe vfio-pci"
            podman exec -it my-rhel-dpdk bash -c "dpdk-devbind.py -b vfio-pci {nic1_bus}"
            podman exec -it my-rhel-dpdk bash -c "dpdk-devbind.py -b vfio-pci {nic2_bus}"
            podman exec -it my-rhel-dpdk bash -c "dpdk-devbind.py -s"
            """
            run(cmd)

        log("start new bash for podman")
        cmd = f"""
        /bin/bash
        """
        obj = start_subprocess(cmd,3)

        cmd = f"""
        podman exec -it my-rhel-dpdk bash -c "dpdk-testpmd -a {nic1_bus} -a {nic2_bus} -- -i --nb-cores=4 --rxq=4 --txq=4 --auto-start"
        """
        write_cmd_input(obj,cmd,10)

        cmd = f"""
        set verbose 9
        show port info all
        show port stats all
        """
        write_cmd_input(obj,cmd,10)
        sync_set(client_target,sync_start)
        sync_wait(client_target,sync_end)
        cmd = f"""
        show port info all
        show port stats all
        stop
        quit
        """
        write_cmd_input(obj,cmd,10)
        out,error = obj.communicate()
        if None != error:
            print(f"{func_name} start testpmd failed")
            print(error.decode())
        print(out.decode())
        with enter_phase(f"{func_name} clear container env"):
            clear_container_env()
            clear_dpdk_interface_by_devbind()
            clear_dpdk_interface_by_driverctl()
    elif i_am_client():
        cmd = f"""
        ip link set {nic1_name} mtu 9600
        ip link set {nic2_name} mtu 9600
        ip link set {nic1_name} up
        ip link set {nic2_name} up
        """
        run(cmd)
        sync_wait(server_target,sync_start)
        with enter_phase(f"{func_name} IPV4 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 2.2.2.2 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet import IP
            size = 64
            pkt = Ether()/IP(src="1.1.1.1",dst="2.2.2.2")
            pkt.dst = nic2_mac
            pkt.type = 0x0800
            pkt.chksum = 0x1234
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        with enter_phase(f"{func_name} IPV6 packets check"):
            pkt_file_name = "abc.cap"
            cmd = f"""
            rm -f {pkt_file_name}
            tcpdump -i {nic2_name} host 3000::200 -w {pkt_file_name} &
            sleep 3
            """
            run(cmd)
            send_pkt_num = 10

            from scapy import all
            from scapy.layers.l2 import Ether
            from scapy.utils import hexdump
            from scapy.sendrecv import sendp
            from scapy.layers.inet6 import IPv6
            size = 64
            pkt = Ether()/IPv6(src="3000::100",dst="3000::200")
            pkt.dst = nic2_mac
            pkt.type = 0x86DD
            payload = max(0, size - len(pkt)) * 'x'
            pkt.add_payload(payload.encode())
            log(pkt.show())
            sendp(pkt,count=send_pkt_num,inter=1,iface=nic1_name)
            #here kill tcpdump and read capture file to get item number
            cmd = f"""
            sleep 3
            pkill tcpdump
            sleep 2
            unset pkt_num
            pkt_num=`tcpdump -r abc.cap -q  | wc -l`
            rlAssertEquals 'check ipv6 receive pkts' '$pkt_num' '{send_pkt_num}'
            """
            print(cmd)
            run(cmd)
        sync_set(server_target,sync_end)
        with enter_phase(f"{func_name} clear container env"):
            clear_container_env()
            clear_dpdk_interface_by_devbind()
            clear_dpdk_interface_by_driverctl()
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_terminate_container_test(vf_spoofchk,vf_trust):
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    clear_container_env()
    clear_dpdk_interface_by_devbind()
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    if i_am_server():
        vf1_list = vf_create_from_pf_mac(nic1_mac,4,vf_spoofchk,vf_trust)
        log(f"{vf1_list}")
        vf_mac_list = []
        vf_pci_list = []
        for i in range(4):
            log(f"{vf1_list[i]}")
            vf_mac_list.append(pysriov.sriov_get_mac_from_name(vf1_list[i]))
            vf_pci_list.append(my_tool.get_bus_from_name(vf1_list[i]))

        log(f"{vf_mac_list}")
        log(f"{vf_pci_list}")

        if system_version_id >= 90:
            image_name = "rhel9-dpdk"
        elif system_version_id >= 80:
            image_name = "rhel8-dpdk21"
        else:
            run("echo 'not support now'")
        cmd = f"""
        podman login -u="wanghekai" -p="gc1UHQzSLlK4zizr3eggM9U5yw9uTUPPYmHgn0uqsG3aEZ/DJQQwFf3XQYC0HBwI" quay.io
        podman pull quay.io/wanghekai/{image_name}
        """
        run(cmd)

        log("start new bash for podman")
        cmd = f"""
        /bin/bash
        """
        obj = start_subprocess(cmd,3)

        for i in range(4):
            enable_dpdk_by_driverctl(vf_mac_list[i])
            cmd = f"""
            nohup podman run -it --name dpdk-con{i} --rm --privileged \
            -v /sys:/sys -v /dev:/dev -v /lib/modules:/lib/modules \
            quay.io/wanghekai/{image_name} \
            dpdk-testpmd -l 0-3 \
            -n 4 -a {vf_pci_list[i]} \
            -- --nb-cores=2 --forward=txonly -i --auto-start &
            """
            write_cmd_input(obj,cmd,10)

        import random
        j = random.choice([0,1,2,3])
        cmd = f"""podman kill dpdk-con{j}"""
        run(cmd)

        cmd = f"""podman container ls"""
        run(cmd)

        cmd = f"""
        /bin/bash
        """
        obj1 = start_subprocess(cmd,3)
        cmd = f"""
            podman run -it --name dpdk-con{j} --rm --privileged \
            -v /sys:/sys -v /dev:/dev -v /lib/modules:/lib/modules \
            quay.io/wanghekai/{image_name} \
            dpdk-testpmd -l 0-3 \
            -n 4 -a {vf_pci_list[j]} \
            -- --nb-cores=2 --forward=txonly -i --auto-start
            """
        write_cmd_input(obj1,cmd,10)

        sync_set(client_target,sync_start)
        sync_wait(client_target,sync_end)
        cmd = f"""
        show port info all
        show port stats all
        show fwd stats all
        stop
        quit
        """
        write_cmd_input(obj1,cmd,10)
        out,error = obj1.communicate()
        if None != error:
            print(f"{func_name} start testpmd failed")
            print(error.decode())
        print(out.decode())
        run(f"kill -9 {obj.pid}")
        with enter_phase(f"{func_name} clear container env"):
            clear_container_env()
            clear_dpdk_interface_by_driverctl()
    elif i_am_client():
        sync_wait(server_target,sync_start)
        sync_set(server_target,sync_end)
        with enter_phase(f"{func_name} clear container env"):
            clear_container_env()
            clear_dpdk_interface_by_driverctl()
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_multi_vfs_creation_test(vf_spoofchk,vf_trust):
    if vf_spoofchk == True:
        vf_spoofchk_str = "-spoofchk-enabled-"
    else:
        vf_spoofchk_str = "-spoofchk-disabled-"
    if vf_trust == True:
        vf_trust_str = "-vf-trust-on"
    else:
        vf_trust_str = "-vf-trust-off"
    func_name = inspect.stack()[0][3] + vf_spoofchk_str + vf_trust_str
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    bus1_info = my_tool.get_bus_from_name(nic1_name)
    base_mac = "0x0000000000"
    import ethtool
    driver_name = ethtool.get_module(nic1_name)
    if i_am_server():
        if driver_name == "mlx5_core":
            mlx_driver_flag = True
        else:
            mlx_driver_flag = False

        cmd = f"""
        ip li set {nic1_name} up
        sleep 3
        """
        run(cmd)

        clear_dpdk_interface_by_driverctl()
        from bash import bash
        max_vfs_cmd = "cat /sys/class/net/" + nic1_name + "/device/sriov_totalvfs"
        max_vfs = int(bash(max_vfs_cmd).value())
        vf1_list = vf_create_from_pf_mac(nic1_mac,max_vfs,vf_spoofchk,vf_trust)
        log(f"{vf1_list}")

        vf_pci_list = []
        for i in range(int(max_vfs)):
            log(f"{vf1_list[i]}")
            vf_pci_list.append(my_tool.get_bus_from_name(vf1_list[i]))

        log(f"{vf_pci_list}")

        for i in range(int(max_vfs)):
            base_mac = "{:012X}".format(int(base_mac, 16) + 1)
            new_mac = ":".join(base_mac[i] + base_mac[i + 1] for i in range(0, len(base_mac), 2))
            cmd = f"""
            ip link set {nic1_name} vf {i} mac {new_mac}
            """
            run(cmd)
            mac_check_cmd = f"ip link show vf1_list[{i}] | grep link/ether | grep {new_mac}"
            run(mac_check_cmd)

        for i in vf_pci_list:
            driver_bind(i,"vfio-pci")

        sync_set(client_target,sync_start)
        sync_wait(client_target,sync_end)

        clear_dpdk_interface_by_driverctl()
        #vf_delete(bus1_info)
    elif i_am_client():
        sync_wait(server_target,sync_start)
        sync_set(server_target,sync_end)
        pass
    else:
        pass

@test_item_check
def dpdk_sriov_bond_vf_test(mode,mac,vf_spoofchk,vf_trust):
    func_name = inspect.stack()[0][3]
    sync_start = func_name + "_start"
    sync_end = func_name + "_end"
    clear_container_env()
    clear_dpdk_interface_by_devbind()
    nic1_mac,nic2_mac = get_nic_mac()
    nic1_name = get_nic_name_from_mac(nic1_mac)
    nic2_name = get_nic_name_from_mac(nic2_mac)
    if i_am_server():
        vf1_list = vf_create_from_pf_mac(nic1_mac,2,vf_spoofchk,vf_trust)
        vf2_list = vf_create_from_pf_mac(nic2_mac,1,vf_spoofchk,vf_trust)
        log(f"{vf1_list} {vf2_list}")
        vf0_name = vf1_list[0]
        vf1_name = vf1_list[1]
        vf2_name = vf2_list[0]
        log(f"{vf0_name} {vf1_name} and {vf2_name}")
        vf0_mac = pysriov.sriov_get_mac_from_name(vf0_name)
        vf1_mac = pysriov.sriov_get_mac_from_name(vf1_name)
        vf2_mac = pysriov.sriov_get_mac_from_name(vf2_name)
        log(f"{vf0_mac} {vf1_mac} and {vf2_mac}")
        bus0_info = my_tool.get_bus_from_name(vf0_name)
        bus1_info = my_tool.get_bus_from_name(vf1_name)
        bus2_info = my_tool.get_bus_from_name(vf2_name)
        log(f"{bus0_info} {bus1_info} and {bus2_info}")
        enable_dpdk_by_driverctl(vf0_mac)
        enable_dpdk_by_driverctl(vf1_mac)
        enable_dpdk_by_driverctl(vf2_mac)
        rx_port_num = 1 if bus1_info < bus2_info else 2
        explicit_mac = mac
        if explicit_mac:
            bond_mac = "aa:bb:cc:dd:ee:ff"
        else:
            bond_mac = vf0_mac

        if system_version_id >= 90:
            image_name = "rhel9-dpdk"
        elif system_version_id >= 80:
            image_name = "rhel8-dpdk21"
        else:
            run("echo 'not support now'")
        cmd = f"""
        podman login -u="wanghekai" -p="gc1UHQzSLlK4zizr3eggM9U5yw9uTUPPYmHgn0uqsG3aEZ/DJQQwFf3XQYC0HBwI" quay.io
        podman pull quay.io/wanghekai/{image_name}
        """
        run(cmd)

        log("start new bash for podman")
        cmd = f"""
        /bin/bash
        """
        obj = start_subprocess(cmd,3)

        vdev_str = (
        f"net_bonding_bond_test,mode={mode},"
        f"slave={bus0_info},slave={bus2_info},"
        f"primary={bus0_info}"
        )

        cmd = f"""
        nohup podman run -it --name dpdk-bond-con --rm --privileged \
        -v /sys:/sys -v /dev:/dev -v /lib/modules:/lib/modules \
        quay.io/wanghekai/{image_name} \
        dpdk-testpmd -l 0-3 -n 4\
        -a {bus0_info} -a {bus1_info} -a {bus2_info}\
        --vdev {vdev_str} \
        -- --forward-mode=mac --portlist {rx_port_num},3 \
        --eth-peer 3,dd:cc:bb:aa:33:00
        """
        write_cmd_input(obj,cmd,10)

        sync_set(client_target,sync_start)
        sync_wait(client_target,sync_end)
        cmd = f"""
        show port info all
        show port stats all
        show fwd stats all
        stop
        quit
        """
        write_cmd_input(obj1,cmd,10)
        out,error = obj.communicate()
        if None != error:
            print(f"{func_name} start testpmd failed")
            print(error.decode())
        print(out.decode())
        run(f"kill -9 {obj.pid}")
        with enter_phase(f"{func_name} clear container env"):
            clear_container_env()
            clear_dpdk_interface_by_driverctl()
    elif i_am_client():
        sync_wait(server_target,sync_start)
        sync_set(server_target,sync_end)
        with enter_phase(f"{func_name} clear container env"):
            clear_container_env()
            clear_dpdk_interface_by_driverctl()
        pass
    else:
        pass

#skip this
# with enter_phase("dpdk_qos_nic_partition_test"):
#     dpdk_qos_nic_partition_test()
#     pass

# #Here Begin DPDK standalone test
TEMP_FILE = "/var/tmp/dpdk-standalone-test-flag"
if __name__ == "__main__":
    send_command("rlJournalStart")
    load_env()
    if not os.path.exists(TEMP_FILE):
        with enter_phase("update beaker tasks repo"):
            update_beaker_tasks_repo()
            pass
        with enter_phase("disable beaker-buildroot repo"):
            disable_beaker_buildroot_repo()
            pass
        with enter_phase("add yum profiles"):
            add_yum_profiles()
            pass
        with enter_phase("install basic package"):
            install_package()
            pass
        with enter_phase("install driver control"):
            install_driverctl()
            pass
        with enter_phase("install dpdk package"):
            install_dpdk()
            pass
        with enter_phase("Update temp file and reboot system"):
            config_hugepage()
            local.path(TEMP_FILE).touch()
            run("rhts-reboot")
            run("cat /proc/cmdline")
    else:
        with enter_phase("init test env after reboot"):
            run("cat /proc/cmdline")
            clear_env()
            init_test_env()
            disable_beaker_buildroot_repo()
        with enter_phase("Init network connection topo"):
            if i_am_server():
                init_physical_topo_without_switch()
                sync_set(client_target,"network_conn_init")
            else:
                # init_netscout_tool()
                # init_netscout_config()
                sync_wait(server_target,"network_conn_init")
                pass
            pass
        with enter_phase("Install dpdk and driverctl"):
            install_dpdk()
            install_driverctl()
            pass
        dpdk_bind_and_unbind_test()
        dpdk_port_info_test()
        dpdk_port_blocklist_test()
        #podman only support rhel8.2 and above
        if system_version_id >= 82:
            dpdk_testpmd_in_container_test()
            dpdk_sriov_vf_bug2088787_test(False, True)
        if dut_nic_driver == "wpc_ice":
            log("SKIP dpdk_port_state_change_test")
            pass
        else:
            if os.environ.get("CONN_TYPE") == "netscout":
                dpdk_port_state_change_test()
            else:
                log("SKIP dpdk_port_state_change_test since connection type is not netscout")
        dpdk_mtu_and_jumbo_packet_test()
        dpdk_mtu_and_jumbo_packet_test(9600,9600)
        dpdk_checksum_offload_test()
        dpdk_tso_test()
        dpdk_gso_and_gro_test()
        dpdk_rss_test()
        dpdk_broadcast_test()
        dpdk_multicast_test()
        dpdk_promisc_test()
        dpdk_vlan_test()
        dpdk_qinq_test()
        # https://bugzilla.redhat.com/show_bug.cgi?id=2144728
        dpdk_tunnel_vxlan_test()
        dpdk_tunnel_gre_test()
        if system_version_id > 82:
            dpdk_virtio_user_as_exceptional_path_ipv4_test()
            dpdk_virtio_user_as_exceptional_path_ipv6_test()
        dpdk_l3_forwarding_test()
        if system_version_id >= 86:
            dpdk_sriov_vf_config_vsi_queues_bug2137378_test(False,True)
            dpdk_sriov_vf_vlan_for_bug_2131310_test(False,True)
        if dpdk_verion >= 22:
            if dpdk_verion == 22:
                if dpdk_minor_version >= 11:
                    dpdk_sriov_vf_bug2091552_test()
            else:
                dpdk_sriov_vf_bug2091552_test()
        dpdk_sriov_vf_bug2091552_test()
        dpdk_sriov_vf_multiple_queues_test(False,True)
        # skip test below since bug https://bugzilla.redhat.com/show_bug.cgi?id=2151748
        # dpdk_sriov_vf_multiple_queues_test(False,True,256)
        dpdk_sriov_vf_func_test(True,True,0)
        dpdk_sriov_vf_func_test(True,False,0)
        dpdk_sriov_vf_func_test(False,True,0)
        dpdk_sriov_vf_func_test(False,False,0)
        dpdk_sriov_vf_func_test(True,True,1024)
        dpdk_sriov_vf_func_test(True,False,1024)
        dpdk_sriov_vf_func_test(False,True,1024)
        dpdk_sriov_vf_func_test(False,False,1024)
        dpdk_sriov_vf_macaddress_test(False,True)
        dpdk_sriov_single_vf_test(True,True)
        if system_version_id >= 86:
            dpdk_sriov_vf_vlan_without_vlan_filter_test(True,True)
            dpdk_sriov_vf_vlan_without_vlan_filter_test(False,True)
        # https://bugzilla.redhat.com/show_bug.cgi?id=2079683
        dpdk_sriov_vf_vlan_test(True,True)
        dpdk_sriov_vf_vlan_test(True,False)
        dpdk_sriov_vf_vlan_test(False,True)
        dpdk_sriov_vf_vlan_test(False,False)
        dpdk_sriov_vf_qinq_test(True,True)
        dpdk_sriov_vf_qinq_test(True,False)
        dpdk_sriov_vf_qinq_test(False,True)
        dpdk_sriov_vf_qinq_test(False,False)
        dpdk_sriov_vf_kernel_vlan_test(True,True,0,0)
        dpdk_sriov_vf_kernel_vlan_test(True,False,0,0)
        dpdk_sriov_vf_kernel_vlan_test(False,True,0,0)
        dpdk_sriov_vf_kernel_vlan_test(False,False,0,0)
        dpdk_sriov_vf_kernel_vlan_test(True,True,1024,0)
        dpdk_sriov_vf_kernel_vlan_test(True,False,1024,0)
        dpdk_sriov_vf_kernel_vlan_test(False,True,1024,0)
        dpdk_sriov_vf_kernel_vlan_test(False,False,1024,0)
        dpdk_sriov_vf_kernel_vlan_test(True,True,0,1024)
        dpdk_sriov_vf_kernel_vlan_test(True,False,0,1024)
        dpdk_sriov_vf_kernel_vlan_test(False,True,0,1024)
        dpdk_sriov_vf_kernel_vlan_test(False,False,0,1024)
        dpdk_sriov_vf_kernel_vlan_test(True,True,1024,1024)
        dpdk_sriov_vf_kernel_vlan_test(True,False,1024,1024)
        dpdk_sriov_vf_kernel_vlan_test(False,True,1024,1024)
        dpdk_sriov_vf_kernel_vlan_test(False,False,1024,1024)
        dpdk_sriov_vf_mtu_test(True,True)
        dpdk_sriov_vf_mtu_test(True,False)
        dpdk_sriov_vf_mtu_test(False,True)
        dpdk_sriov_vf_mtu_test(False,False)
        dpdk_sriov_vf_broadcast_test(True,True)
        dpdk_sriov_vf_broadcast_test(True,False)
        dpdk_sriov_vf_broadcast_test(False,True)
        dpdk_sriov_vf_broadcast_test(False,False)
        dpdk_sriov_vf_multicast_test(True,True)
        dpdk_sriov_vf_multicast_test(True,False)
        dpdk_sriov_vf_multicast_test(False,True)
        dpdk_sriov_vf_multicast_test(False,False)
        dpdk_sriov_vf_promisc_test(True,True)
        dpdk_sriov_vf_promisc_test(True,False)
        dpdk_sriov_vf_promisc_test(False,True)
        dpdk_sriov_vf_promisc_test(False,False)
        if system_version_id >= 84:
            dpdk_sriov_vf_promisc_bug2101710_test(True,True)
        dpdK_sriov_vf_in_guest_test(False,True)
        # dpdK_sriov_vf_in_guest_bug2143985_test(False,True)
        dpdk_flow_bifurcation_test()
        dpdk_testpmd_l2_performance_test(32)
        # https://access.redhat.com/support/cases/#/case/03274516
        # skip this case now since it is a bug https://bugzilla.redhat.com/show_bug.cgi?id=2112497
        # dpdk_testpmd_l2_performance_test(4)
        dpdk_sriov_testpmd_in_guest_performance_test(False,True)
        dpdk_sriov_terminate_container_test(True,False)
        dpdk_sriov_multi_vfs_creation_test(True,False)
    send_command("rlJournalEnd")
    basic_send_command("exit")
    exit(0)
