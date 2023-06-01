#!/usr/bin/env python3

import sys
import xml.etree.ElementTree as ET


class XmlTool(object):

    def __init__(self):
        self.default_code = sys.getdefaultencoding()

    def xml_get_name(self, xml_file):
        """
        <domain type='kvm'>
        <name>guest30032</name>
        <uuid>37425e76-af6a-44a6-aba0-73434afe34c0</uuid>
        </domain>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        name_item = ET.ElementPath.find(root, "./name")
        if name_item != None:
            return name_item.text
        else:
            return ""

    def xml_get_uuid_from_xml_file(self, xml_file):
        """
        <domain type='kvm'>
        <name>guest30032</name>
        <uuid>37425e76-af6a-44a6-aba0-73434afe34c0</uuid>
        </domain>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        uuid_item = ET.ElementPath.find(root, "./uuid")
        if uuid_item != None:
            return uuid_item.text
        else:
            return ""

    def xml_update_guestname_and_uuid(self, xml_file, name, uuid):
        """
        <domain type='kvm'>
        <name>guest30032</name>
        <uuid>37425e76-af6a-44a6-aba0-73434afe34c0</uuid>
        </domain>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        name_item = ET.ElementPath.find(root, "./name")
        uuid_item = ET.ElementPath.find(root, "./uuid")
        if name_item is not None and name is not None:
            name_item.text = str(name)
        if uuid_item is not None and uuid is not None:
            uuid_item.text = str(uuid)
        tree.write(xml_file)

    def xml_add_vcpupin_item(self, xml_file, num):
        """
        <vcpu placement="static">3</vcpu>
        <cputune>
            <vcpupin cpuset="1" vcpu="0" />
            <vcpupin cpuset="2" vcpu="1" />
            <vcpupin cpuset="3" vcpu="2" />
        </cputune>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        vcpu_item = ET.ElementPath.find(root, "./vcpu")
        current_num = 0
        if None != vcpu_item:
            current_num = int(vcpu_item.text)
            vcpu_item.text = str(num)
        item = ET.ElementPath.find(root, "./cputune")
        sub_item = ET.ElementPath.find(root, "./cputune/vcpupin")
        if num > current_num:
            for i in range(num-current_num):
                item.append(sub_item)
        sub_item_list = list(item)
        for i in range(sub_item_list.__len__()):
            sub_item_list[i].set(str("vcpu"), str(i))
            sub_item_list[i].set(str("cpuset"), str(i))
        sub_item_list.sort()

        print(ET.tostringlist(item))
        tree.write(xml_file)

    def update_vcpu(self, xml_file, index, value):
        """
        <cputune>
        <vcpupin cpuset="1" vcpu="8" />
        <vcpupin cpuset="2" vcpu="3" />
        <vcpupin cpuset="3" vcpu="4" />
        <emulatorpin cpuset='1'/>
        </cputune>
        """
        tree = ET.parse(xml_file)
        item = tree.find("cputune")
        item[index].set(str("cpuset"), str(value))
        tree.write(xml_file)

    def update_vcpu_emulatorpin(self, xml_file, value):
        """
        <cputune>
        <vcpupin cpuset="1" vcpu="8" />
        <vcpupin cpuset="2" vcpu="3" />
        <vcpupin cpuset="3" vcpu="4" />
        <emulatorpin cpuset='1'/>
        </cputune>
        """
        tree = ET.parse(xml_file)
        item = tree.find("./cputune/emulatorpin")
        item.set(str("cpuset"), str(value))
        tree.write(xml_file)

    def update_numa(self, xml_file, value):
        """
        <numatune>
        <memory mode='strict' nodeset='0'/>
        </numatune>
        """
        tree = ET.parse(xml_file)
        item = tree.find("numatune")
        item[0].set("nodeset", str(value))
        tree.write(xml_file)

    def update_image_source(self, xml_file, image_name):
        """
        <devices>
            <emulator>/usr/libexec/qemu-kvm</emulator>
            <disk device="disk" type="file">
                    <driver name="qemu" type="qcow2" />
                    <source file="/root/rhel.qcow2" />
                    <target bus="virtio" dev="vda" />
                    <address bus="0x01" domain="0x0000" function="0x0" slot="0x00" type="pci" />
            </disk>
        """
        tree = ET.parse(xml_file)
        root = tree.getroot()
        source_item = ET.ElementPath.find(root, "./devices/disk/source")
        source_item.set(str("file"), str(image_name))
        tree.write(xml_file)

    def update_vhostuser_interface(self, xml_file, mac):
        """
        <interface type='vhostuser'>
        <mac address='52:54:00:11:8f:ea'/>
        <source type='unix' path='/tmp/vhost0' mode='server'/>
        <model type='virtio'/>
        <driver name='vhost' iommu='on' ats='on'/>
        <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
        </interface>
        """

        tree = ET.parse(xml_file)
        item_list = tree.findall("devices/interface")
        for item in item_list:
            if item.get("type") == "vhostuser":
                item[0].set("address", str(mac))
        tree.write(xml_file)

    def update_bridge_interface(self, xml_file, mac, index=0):
        """
        <interface type='bridge'>
        <mac address='52:54:00:bb:63:7b'/>
        <source bridge='virbr0'/>
        <model type='virtio'/>
        <address type='pci' domain='0x0000' bus='0x02' slot='0x00' function='0x0'/>
        </interface>
        """
        tree = ET.parse(xml_file)
        item_list = tree.findall("./devices/interface[@type='bridge']")
        item = item_list[index]
        if None != item:
            item[0].set("address", str(mac))
        tree.write(xml_file)

    def format_item(self, info, format_list):
        if info:
            return str(info).format(*format_list)

    def add_item_from_xml(self, xml_file, parent_path, xml_info):
        tree = ET.parse(xml_file)
        item = ET.fromstring(xml_info)
        root = tree.getroot()
        parent_item = ET.ElementPath.find(root, parent_path)
        # Here if use if parent_item, this will false when parent_item have no child
        if None != parent_item:
            parent_item.append(item)
        tree.write(xml_file)

    def remove_item_from_xml(self, xml_file, path, index=None):
        tree = ET.parse(xml_file)
        root = tree.getroot()
        parent_path = path + "/.."
        parent_item = ET.ElementPath.find(root, parent_path)
        item_list = ET.ElementPath.findall(root, path)
        if None is index:
            for item in item_list:
                parent_item.remove(item)
        else:
            parent_item.remove(item_list[int(index)])
        tree.write(xml_file)

    def get_pci_address_of_vm_hostdev(self, xml_file, index=0):
        """
        <interface type='hostdev' managed='yes'>
                <mac address='52:54:00:7e:f4:6d'/>
                <driver name='vfio'/>
                <source>
                <address type='pci' domain='0x0000' bus='0x04' slot='0x10' function='0x1'/>
                </source>
                <alias name='hostdev1'/>
                <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
        </interface>
        """

        all_hostdev_item = []
        tree = ET.parse(xml_file)
        item_list = tree.findall("devices/interface")
        for item in item_list:
            if item.get("type") == "hostdev":
                all_hostdev_item.append(item)
        if len(all_hostdev_item) > index:
            all_str = ""
            for i in list(all_hostdev_item[index]):
                if i.tag == "address" and i.get("type") == "pci":
                    all_str += str(i.get("domain"))[2:]
                    all_str += ":"
                    all_str += str(i.get("bus"))[2:]
                    all_str += ":"
                    all_str += str(i.get("slot"))[2:]
                    all_str += "."
                    all_str += str(i.get("function"))[2:]
                    break
            return all_str
        else:
            return ""

    def get_mac_address_of_vm_hostdev(self, xml_file, index=0):
        """
        <interface type='hostdev' managed='yes'>
            <mac address='52:54:00:7e:f4:6d'/>
            <driver name='vfio'/>
            <source>
                <address type='pci' domain='0x0000' bus='0x04' slot='0x10' function='0x1'/>
            </source>
        <alias name='hostdev1'/>
        <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
        </interface>
        """

        all_hostdev_item = []
        tree = ET.parse(xml_file)
        item_list = tree.findall("devices/interface")
        for item in item_list:
            if item.get("type") == "hostdev":
                all_hostdev_item.append(item)
        if len(all_hostdev_item) > index:
            all_str = ""
            for i in list(all_hostdev_item[index]):
                if i.tag == "mac":
                    all_str = str(i.get("address"))
                    break
            return all_str
        else:
            return ""


if __name__ == '__main__':
    import fire
    fire.Fire(XmlTool)
