#!/usr/bin/env python3

import base64
import io
import json
import os
import select
import subprocess as sp
import sys
import xml.etree.ElementTree as xml

import ethtool
import fire
import napalm
import paramiko
import pexpect
import serial
from plumbum import local
from shell import Shell, shell

"""
# tuned configuration

[main]
summary=Optimize for CPU and hugepage
include=cpu-partitioning

[bootloader]
cmdline=abc=ddd

"""


"""

"""

switch_info = {
    "3548": {}
}


def run_and_getout(command):
    fd = sp.Popen(command, shell=True, stdout=sp.PIPE)
    return fd.communicate()[0]


class Tools(object):
    def __init__(self):
        self.default_code = sys.getdefaultencoding()
        pass

    def get_nic_driver_from_name(self, name):
        if name:
            return ethtool.get_module(name)
        else:
            return ""

    def get_bus_from_name(self, name):
        if name:
            return ethtool.get_businfo(name)
        else:
            return ""

    def get_mac_from_name(self, name):
        if name:
            return ethtool.get_hwaddr(name)
        else:
            return ""

    def get_nic_name_from_mac(self, mac):
        if not mac:
            return "name-error"
        temp_path = local.path("/sys/class/net")
        for i in temp_path:
            if i.is_symlink():
                temp_mac = ethtool.get_hwaddr(str(i.name))
                if temp_mac == mac:
                    return i.name

        return "name-error"

    def get_random_mac_addr(self):
        import random
        mac = [
            0x52,
            0x54,
            0x11,
            random.randint(0x00, 0xff),
            random.randint(0x00, 0xff),
            random.randint(0x00, 0xff)
        ]
        return ':'.join(map(lambda x: "{:02x}".format(x), mac))

    def config_ssh_trust(self, file_name, remote_host, username, password):
        client = paramiko.SSHClient()
        client.load_system_host_keys()
        # client.set_missing_host_key_policy(paramiko.WarningPolicy())
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        with open(file_name, "r") as fd:
            kaizi = fd.read()
        client.connect(remote_host, username=username, password=password)
        client.exec_command("mkdir -p /root/.ssh/")
        client.exec_command('test -f /root/.ssh/known_hosts || touch /root/.ssh/known_hosts')
        client.exec_command("chmod go-w ~/")
        client.exec_command("chmod 700 ~/.ssh")
        client.exec_command("chmod 600 ~/.ssh/authorized_keys")
        cmd = "echo %s >> /root/.ssh/authorized_keys" % (kaizi.strip('\n'))
        client.exec_command(cmd)
        client.close()

    # def get_vm_address(self,remote_host,username, password,mac_addr):
    #     import sys
    #     if sys.version_info.major == 2:
    #         return "Invalid_python_version"
    #     client = paramiko.SSHClient()
    #     client.load_system_host_keys()
    #     client.set_missing_host_key_policy(paramiko.WarningPolicy())
    #     client.connect(remote_host, username=username, password=password)
    #     cmd = f""" virsh net-dhcp-leases default | grep '{mac_addr}' | awk '{{print $5}}' | awk -F '/' '{{print $1}}' """
    #     _,vm_addr,_ = client.exec_command(cmd)
    #     result = vm_addr.read()
    #     client.close()
    #     return result.decode().strip('\n')

    def get_vm_address(self,remote_host,username, password):
        import sys
        if sys.version_info.major == 2:
            return "Invalid_python_version"
        client = paramiko.SSHClient()
        client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.WarningPolicy())
        client.connect(remote_host, username=username, password=password)
        cmd = f""" cat /tmp/vm_address """
        _,vm_addr,_ = client.exec_command(cmd)
        result = vm_addr.read()
        client.close()
        return result.decode().strip('\n')


    def get_remote_host_cmd_result(self,remote_host,username, password,cmd):
        client = paramiko.SSHClient()
        client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.WarningPolicy())
        client.connect(remote_host, username=username, password=password)
        _,ret,_ = client.exec_command(cmd)
        result = ret.read()
        client.close()
        return result.decode().strip('\n')

    def get_isolate_cpus(self):
        """Here Get all cpu from this system without cpu0"""

        command = "cat /proc/cpuinfo | grep processor | awk '{print $NF}'"
        out = run_and_getout(command)
        str_out = out.decode(self.default_code).replace('\n', ' ').strip()
        str_out = str(str_out)
        if str_out[0] == "0":
            return str_out[2:]
        else:
            return str_out

    def get_isolate_cpus_on_numa(self, numa):
        cpu_cmd = "lscpu | grep 'NUMA node%s' | awk '{print $NF}'" % (
            str(int(numa)))
        cpu_info = run_and_getout(cpu_cmd)
        str_out = cpu_info.decode(self.default_code).strip()
        # 0,1,2,3,4
        # 0-9,9-29
        temp_list = str(str_out).split(',')
        all_str = ""
        for i in temp_list:
            if '-' in i:
                start_index = int(str(i).split('-')[0])
                last_index = int(str(i).split('-')[-1])+1
                all_str += " ".join([str(i)
                                     for i in range(start_index, last_index)]) + " "
            else:
                all_str += str(i)
                all_str += " "

        all_str = all_str.strip()
        if all_str[0] == "0":
            return all_str[2:]
        else:
            return all_str

    def get_isolate_cpus_with_nic(self, nic_name):
        """
            First get cpu numa node and then get cpu list without cpu 0
        """
        cmd = "cat /sys/class/net/{}/device/numa_node".format(str(nic_name))
        out = run_and_getout(cmd)
        return self.get_isolate_cpus_on_numa(out)

    def get_pmd_masks(self, str_cpulist):
        ret_val = 0x0
        if str_cpulist == None or str_cpulist == "":
            return 0x0
        else:
            # print(type(str_cpulist))
            if isinstance(str_cpulist, str):
                for i in str_cpulist.split():
                    ret_val |= 0x1 << int(i)
                return hex(ret_val)
            else:
                ret_val |= 0x1 << int(str_cpulist)
                return hex(ret_val)
        pass

    def make_xena_config(self, template_file, module_index):
        if os.path.exists(template_file):
            fd = open(template_file, "r")
            if fd:
                data_json = json.loads(fd.read())
                fd.close()
                data_json['PortHandler']['EntityList'][0]['PortRef']['ModuleIndex'] = module_index
                # data_json['PortHandler']['EntityList'][1]['PortRef']['ModuleIndex'] = module_index
                # here means 100G
                if module_index == 5:
                    data_json['PortHandler']['EntityList'][0]['EnableFec'] = "false"
                    # data_json['PortHandler']['EntityList'][1]['EnableFec'] = "false"
            else:
                print("Can not open %s File " % (template_file))
                return
            with open(template_file, "w") as nfd:
                nfd.write(json.dumps(data_json, indent=4))
        else:
            pass
        pass

    def run_cmd_get_output(self, pts, cmd, end_flag="]#"):
        if not os.path.exists(pts):
            return "pts not found"
        sr = serial.Serial(pts, 115200, timeout=1)
        if not sr:
            return "open dev pts failed"
        sio = io.TextIOWrapper(io.BufferedRWPair(sr, sr))
        sio.write(os.linesep)
        sio.flush()
        while True:
            data = sio.readline()
            if data == '':
                continue
            else:
                # print(data)
                if "login:" in data and "root" not in data:
                    sio.write("root" + os.linesep)
                    sio.flush()
                elif "Password:" in data:
                    sio.write("redhat" + os.linesep)
                    sio.flush()
                elif "]#" in data or end_flag in data:
                    break
                else:
                    continue
        cmd = cmd + os.linesep
        all_data = ""
        cmds = cmd.split(os.linesep)
        cmds = [i.strip() for i in cmds]
        cmds = [i for i in cmds if len(i) > 0]
        for cmd in cmds:
            while True:
                data = sio.readline()
                if len(data) == 0:
                    sio.write(os.linesep)
                    sio.flush()
                else:
                    # print(data)
                    if "]#" in data or end_flag in data:
                        sio.write(cmd + os.linesep)
                        sio.flush()
                        break
                    else:
                        continue
            while True:
                data = sio.readline()
                if len(data) == 0:
                    sio.write(os.linesep)
                    sio.flush()
                else:
                    # print(data)
                    if "]#" in data or end_flag in data:
                        break
                    else:
                        if len(data.strip(os.linesep)):
                            all_data = all_data + data

        return all_data

    def login_vm_and_run_cmds(self, vm_domain, cmds, prompt=None):
        patterm = ["login:", "Password:", "]#", pexpect.EOF,
                   pexpect.TIMEOUT, r"Escape character is \^]"]
        child = pexpect.spawn("virsh console gg")
        child.logfile = None
        child.logfile_read = sys.stdout.buffer
        child.logfile_send = None
        err_flag = False
        if None == prompt:
            prompt = "]#"
        while True:
            index = child.expect(patterm)
            if index == 0:
                child.sendline("root")
            elif index == 1:
                child.sendline("redhat")
            elif index == 2:
                break
            elif index == 3:
                break
            elif index == 4:
                print("Timeout error")
                err_flag = True
                break
            elif index == 5:
                child.sendline("")
                child.send(chr(3))
            else:
                err_flag = True
                print("unknow virsh console return str")
                child.send(chr(3))
                break
        if err_flag:
            return -1
        cmd_list = cmds.split('\n')
        # print(cmd_list)
        for c in cmd_list:
            child.sendline(c.strip('{ }'))
            child.expect(prompt)
            if prompt == "]#":
                child.sendline("echo $?")
                child.expect(prompt)
        sys.stdout.flush()
        child.close()
        return 0

    def get_switch_port_info(self, sw_name, sw_port):
        if str(sw_name).__len__() == 0 or str(sw_port).__len__() == 0:
            return ""
        self.sw_os_type = switch_info[str(sw_name)]["ostype"]
        self.sw_info = switch_info[str(sw_name)]
        """
		SUPPORTED_DRIVERS = [
                    "base",
                    "eos",
                    "ios",
                    "iosxr",
                    "junos",
                    "nxos",
                    "nxos_ssh",
        ]
		"""
        """
		"6004" : {
		}
		"""
        self.sw_driver = napalm.get_network_driver(self.sw_os_type)
        if self.sw_driver:
            self.sw_device = self.sw_driver(
                self.sw_info["host"], self.sw_info["user"], self.sw_info["password"])
            self.sw_device.open()
            # napalm.nxos_ssh.NXOSSSHDriver._send_command_list
            # napalm.nxos_ssh.NXOSSSHDriver.get_interfaces()
            # napalm.junos.JunOSDriver.get_interfaces
            self.inter_dict = self.sw_device.get_interfaces()
            #import pprint
            # pprint.pprint(self.inter_dict)
            temp_port_info = str(sw_port).replace("Eth", "Ethernet")

            port_info = self.inter_dict[temp_port_info]["is_up"]
            return port_info
        else:
            return ""


if __name__ == '__main__':
    import fire
    fire.Fire(Tools)
