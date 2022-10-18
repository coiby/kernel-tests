#! /usr/bin/python3
import sys
import getopt
from os.path import basename
from rt_kernel_setup import main as setup


def parse_args():
    # global type
    # global vm_names
    # global mac4vm1
    # global mac4vm1if2
    # global mac4vm2
    # global vm_cpunum
    # global rhel_image_name
    global params

    if len(sys.argv) <= 1:
        return
    try:
        opts, args = getopt.getopt(sys.argv[1:], "h",
                                   [
                                    "help", "os_type=","stage=","vm_names=","mac4vm1=","mac4vm1if2=","mac4vm2=",
                                    "vm_cpunum=","rhel_image_name=","enable_default_yum=","vm_kernel_name=",
                                    "enable_vm_xml_tuning=", "brew_task_id=", "kernel_repo=", "test_nic="
                                    ])
    except getopt.GetoptError as error:
        print(str(error))
        print("Run '%s --help' for further information" % sys.argv[0])
        sys.exit(1)
    for opt, arg in opts:
        if opt == "--help":
            usage()
            sys.exit(0)
        if opt == "--os_type":
            params.update({"os_type": arg})
            print(f"os_type={arg}")
        if opt == "--stage":
            params.update({"stage": arg})
            print(f"stage={arg}")
        if opt == "--vm_names":
            params.update({"vm_names": arg.split(",")})
            print(f"vm_names={arg}")
        if opt == "--mac4vm1":
            params.update({"mac4vm1": arg})
            print(f"mac4vm1={arg}")
        if opt == "--mac4vm1if2":
            params.update({"mac4vm1if2": arg})
            print(f"mac4vm1if2={arg}")
        if opt == "--mac4vm2":
            params.update({"mac4vm2": arg})
            print(f"mac4vm2={arg}")
        if opt == "--vm_cpunum":
            params.update({"vm_cpunum":arg})
            print(f"vm_cpunum={arg}")
        if opt == "--rhel_image_name":
            params.update({"rhel_image_name": arg})
            print(f"rhel_image_name={arg}")
        if opt == "--enable_default_yum":
            params.update({"enable_default_yum": arg})
            print(f"enable_default_yum={arg}")
        if opt == "--vm_kernel_name":
            if arg == 'None':
                arg=None
            params.update({"vm_kernel_name": arg})
            print(f"vm_kernel_name={arg}")
        if opt == "--enable_vm_xml_tuning":
            params.update({"enable_vm_xml_tuning": arg})
            print(f"enable_vm_xml_tuning={arg}")
        if opt == "--brew_task_id":
            if arg == 'None':
                arg=None
            params.update({"brew_task_id": arg})
            print(f"brew_task_id={arg}")
        if opt == "--kernel_repo":
            if arg == 'None':
                arg=None
            params.update({"kernel_repo": arg})
            print(f"kernel_repo={arg}")
        if opt == "--test_nic":
            if arg == 'None' or arg == "mac2name-error":
                arg=None
            params.update({"test_nic": arg})
            print(f"test_nic={arg}")

def usage():
    argv0 = basename(sys.argv[0])
    print(f"""
Usage:
-----
    {argv0} [options]

options:
    --help, --usage:
        Disply usage info

    --os_type:
        vm/host

    --stage:
        0 is install rt-tests/tuned/qemu-kvm-rhev/libvirt and configure hugepage and cpu isolate
        1 is check hugepage setting, cpu setting and install package setting.

    --vm_names:
        only support create two vms, and must write like "vm1,vm2"
    
    --mac4vm1:
        vm1 interface1
    
    --mac4vm1if2:
        vm1 interface2
        
    --mac4vm2:
        vm2 interface1
        
    --vm_cpunum:
        spicefy vm cpu number, The sum of vm_cpunum of two virtual machines cannot exceed the number of CPUs of one numa 
        node of the host node.
        
    --rhel_image_name:
        specify the vm image. If this parameter is not specified, rhel8.2 is used by default.

    --enable_default_yum:
        only accept 'yes' or 'no', the 'yes' will install with beaker-NFV. And 'no' the host will install kernel from runtest --nvr
        and vm will install kernel-rt from brew.
    
    --vm_kernel_name:
        It can be used only when enable_default_yum=no.
        only accept string format as 'kernel-rt-4.18.0-193.30.1.rt13.79.el8_2' or kernel-4.18.0-240.8.el8.dt4

    --enable_vm_xml_tuning:
        this parameter default is 'yes'. It will let script to configure vm isolate and numa in xml. But if change to
        'no', script will not tuning vm xml. It will use virt-install to install a vm.
    
    --brew_task_id:
        use brew task id to install kernel. example: brew download-task $task_id
    
    --kernel_repo:
        use a repo url to install kernel. example: http://brew-task-repos.usersys.redhat.com/repos/scratch/jkc/kernel-rt/4.18.0/305.40.1.rt7.112.el8_4.2021326.ccd3be91/
    
Examples:
Install rt-kernel in host, Configure huge page and tuning CPU. 
# python3 rt-kernel-setup.py --os_type host --stage 0

Install rt-kernel from default repo in vm. Configure huge page and tuning CPU.
# python3 ./rt-kernel/rt_kernel_paramter.py --os_type="vm" --vm_names="g1,g2" --mac4vm1="00:de:ad:02:00:01" 
--mac4vm1if2="00:de:ad:02:00:02" --mac4vm2="00:de:ad:02:00:03" --vm_cpunum="5" --rhel_image_name="rhel8.3.qcow2" 
--enable_default_yum="yes" --enable_vm_xml_tuning="yes" --test_nic=ens1f0

Install rt-kernel from specidied kernel in vm. Configure huge page and tuning CPU.
# python3 ./rt-kernel/rt_kernel_paramter.py --os_type="vm" --vm_names="g1,g2" --mac4vm1="00:de:ad:02:00:01" 
--mac4vm1if2="00:de:ad:02:00:02" --mac4vm2="00:de:ad:02:00:03" --vm_cpunum="5" --rhel_image_name="rhel8.3.qcow2" 
--enable_default_yum="no" --vm_kernel_name="kernel-rt-4.18.0-246.rt14.11.el8" --enable_vm_xml_tuning="yes" --test_nic=ens1f0

Install rt-kernel from default repo in vm. Don't configure cpu isolated and numapin in xml.
# python3 ./rt-kernel/rt_kernel_paramter.py --os_type="vm" --vm_names="g1,g2" --mac4vm1="00:de:ad:02:00:01" 
--mac4vm1if2="00:de:ad:02:00:02" --mac4vm2="00:de:ad:02:00:03" --vm_cpunum="5" --rhel_image_name="rhel8.3.qcow2" 
--enable_default_yum="no" --vm_kernel_name="kernel-rt-4.18.0-246.rt14.11.el8" --enable_vm_xml_tuning="no" --test_nic=ens1f0

    """ )
    return


if __name__ == '__main__':
    params = dict()
    parse_args()
    setup(**params)
