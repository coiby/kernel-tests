#!/usr/bin/python
# Copyright (c) 2016 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Ken Benoit

"""
The functional.connection.setup.test module provides a class (Test) that sets up
a Bluetooth connection.

"""

__author__ = 'Ken Benoit'

import os
import json
import tempfile
import shutil
import filecmp
import time
import socket

import dbus
import dbus.service
import dbus.mainloop.glib

import functional.connection.functional_connection_base
from base.exception.test import *
from worknode.linux.manager.exception.file_system import *

BLUEZ_SERVICE = "org.bluez"
BLUEZ_AGENT_INTERFACE = 'org.bluez.Agent1'
BLUEZ_AGENT_MANAGER_INTERFACE = 'org.bluez.AgentManager1'

BLUEZ_ADAPTER_INTERFACE = "org.bluez.Adapter1"

BLUEZ_OBEX_SERVICE = "org.bluez.obex"
BLUEZ_OBEX_AGENT_INTERFACE = 'org.bluez.obex.Agent1'
BLUEZ_OBEX_AGENT_MANAGER_INTERFACE = 'org.bluez.obex.AgentManager1'
BLUEZ_OBEX_TRANSFER_INTERFACE = 'org.bluez.obex.Transfer1'

class Agent (dbus.service.Object):
    def __init__(self, bus, path, obex):
        super(Agent, self).__init__(bus, path)
        self.obex = obex

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "", out_signature = "")
    def Release (self):
        print ("Release")
        self.obex.dbus_obj.loop.quit ()

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "o", out_signature = "s")
    def RequestPinCode (self, device):
        print ("RequestPinCode (%s)" % (device))
        return "123456"

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "os", out_signature = "")
    def DisplayPinCode (self, device, pincode):
        print ("DisplayPinCode (%s, %s)" % (device, pincode))
        return

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "o", out_signature = "u")
    def RequestPasskey (self, device):
        print ("RequestPasskey (%s)" % (device))

        system_bus = self.obex.dbus_obj.system_bus
        obj = system_bus.get_object (BLUEZ_SERVICE, device)
        iface = dbus.Interface (obj, "org.freedesktop.DBus.Properties")

        iface.Set (BLUEZ_DEVICE_INTERFACE, "Trusted", True)
        passkey = raw_input ("Enter passkey: ")
        return dbus.UInt32 (passkey)

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "ouq", out_signature = "")
    def DisplayPasskey (self, device, passkey, entered):
        print ("DisplayPasskey (%s, %06u entered %u)" % (device, passkey, entered))
        return

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "ou", out_signature = "")
    def RequestConfirmation (self, device, passkey):
        print ("RequestConfirmation (%s, %06d)" % (device, passkey))
        return

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "o", out_signature = "")
    def RequestAuthorization (self, device):
        print ("RequestAuthorization (%s)" % (device))
        return

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "os", out_signature = "")
    def AuthorizeService (self, device, uuid):
        print ("AuthorizeService (%s, %s)" % (device, uuid))
        return

    @dbus.service.method (BLUEZ_AGENT_INTERFACE, in_signature = "", out_signature = "")
    def Cancel (self):
        print ("Cancel")
        return


class ObexAgent (dbus.service.Object):
    def __init__(self, bus, path, obex):
        super(ObexAgent, self).__init__(bus, path)
        self.obex = obex

    @dbus.service.method (BLUEZ_OBEX_AGENT_INTERFACE, in_signature = "", out_signature = "")
    def Release (self):
        print ("Release")
        self.obex.dbus_obj.loop.quit ()

    @dbus.service.method (BLUEZ_OBEX_AGENT_INTERFACE, in_signature = "o", out_signature = "s")
    def AuthorizePush (self, transfer_path):
        session_bus = self.obex.dbus_obj.session_bus
        obj = session_bus.get_object (BLUEZ_OBEX_SERVICE, transfer_path)
        transfer = dbus.Interface (obj, 'org.freedesktop.DBus.Properties')
        name = transfer.Get (BLUEZ_OBEX_TRANSFER_INTERFACE, 'Name')
        print ("AuthorizePush (%s, %s)" % (transfer_path, name))
        return name

    @dbus.service.method (BLUEZ_OBEX_AGENT_INTERFACE, in_signature = "", out_signature = "")
    def Cancel (self):
        print ("Cancel")


class Test(functional.connection.functional_connection_base.FunctionalConnectionBaseTest):
    """
    Test sets up a Bluetooth connection.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.remote_device = None
        self.preconfigured_setups_file = 'preconfigured_setups.json'

        self.set_test_name(
            name = '/kernel/bluetooth_tests/functional/connection/obex'
        )
        self.set_test_author(
            name = 'Don Zickus',
            email = 'dzickus@redhat.com',
        )
        self.set_test_description(
            description = 'Test OBEX server interface'
        )

        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.start_bluetooth_service,
        )
        self.add_test_step(
            test_step = self.set_access_type,
            test_step_description = 'Set the access to OBEX',
        )
        self.add_test_step(
            test_step = self.choose_test_bluetooth_interface,
            test_step_description = 'Choose which Bluetooth interface to use and describe it',
        )
        self.add_test_step(
            test_step = self.run_obex_server,
            test_step_description = 'Run the OBEXd server',
        )

    def set_access_type(self):
        self.work_node.get_bluetooth_component_manager().set_access_type("obex")

    def create_vcard_file (self, path, full_name):
        with open (path,'w') as f:
            f.write ('BEGIN:VCARD\n')
            f.write ('VERSION:3.0\n')
            name = full_name.replace (' ', ';')
            f.write ('N:' + name + '\n')
            f.write ('FN:' + full_name + '\n')
            f.write ('TEL;TYPE=voice,work,pref:+49123456789\n')
            f.write ('END:VCARD\n')


    def create_directory_structure (self):
        home_directory = os.environ['HOME']

        try:
            os.mkdir (home_directory + '/map-messages/')
            os.mkdir (home_directory + '/map-messages/inbox/')
        except Exception as e:
            pass

        try:
            os.mkdir (home_directory + '/phonebook/')
            os.mkdir (home_directory + '/phonebook/telecom')
            os.mkdir (home_directory + '/phonebook/telecom/cch/')
            os.mkdir (home_directory + '/phonebook/telecom/ich/')
            os.mkdir (home_directory + '/phonebook/telecom/mch/')
            os.mkdir (home_directory + '/phonebook/telecom/och/')
            os.mkdir (home_directory + '/phonebook/telecom/pb/')
        except Exception as e:
            pass

        self.create_vcard_file (home_directory + '/phonebook/telecom/cch/1.vcf', 'Incoming1')
        self.create_vcard_file (home_directory + '/phonebook/telecom/cch/2.vcf', 'Incoming2')
        self.create_vcard_file (home_directory + '/phonebook/telecom/cch/3.vcf', 'Incoming3')
        self.create_vcard_file (home_directory + '/phonebook/telecom/cch/4.vcf', 'Outgoing1')
        self.create_vcard_file (home_directory + '/phonebook/telecom/cch/5.vcf', 'Outgoing2')
        self.create_vcard_file (home_directory + '/phonebook/telecom/cch/6.vcf', 'Missed1')

        self.create_vcard_file (home_directory + '/phonebook/telecom/ich/1.vcf', 'Incoming1')
        self.create_vcard_file (home_directory + '/phonebook/telecom/ich/2.vcf', 'Incoming2')
        self.create_vcard_file (home_directory + '/phonebook/telecom/ich/3.vcf', 'Incoming3')

        self.create_vcard_file (home_directory + '/phonebook/telecom/och/1.vcf', 'Outgoing1')
        self.create_vcard_file (home_directory + '/phonebook/telecom/och/2.vcf', 'Outgoing2')

        self.create_vcard_file (home_directory + '/phonebook/telecom/mch/1.vcf', 'Missed1')

        self.create_vcard_file (home_directory + '/phonebook/telecom/pb/0.vcf', 'My Self')

        self.create_vcard_file (home_directory + '/.cache/obexd/vcard.vcf', 'My vCard')


    def remove_directory_structure (self):
        home_directory = os.environ['HOME']

        try:
            shutil.rmtree (home_directory + '/map-messages/', ignore_errors = True)
            shutil.rmtree (home_directory + '/phonebook/', ignore_errors = True)
        except Exception as e:
            pass


    def run_obex_server(self):
        #setup the remote connection
        try:
            obex = self.test_interface._get_command_object('obex')
            self.create_directory_structure ()
        except Exception as e:
            raise TestFailure(e)

        agent_path = '/certification/agent'
        obex_agent_path = '/certification/obex/agent'
        hostname = socket.gethostname()

        Agent(obex.dbus_obj.system_bus, agent_path, obex)
        ObexAgent(obex.dbus_obj.session_bus, obex_agent_path, obex)

        try:
            obex.register_agent(agent_path, security='NoInputNoOutput', default=True)
            obex.register_obex_agent(obex_agent_path)
        except Exception as e:
            self.remove_directory_structure ()
            raise TestFailure(e)

        adapter_properties = dbus.Interface(obex.adapter, dbus.PROPERTIES_IFACE)
        adapter_properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Discoverable', True)
        adapter_properties.Set (BLUEZ_ADAPTER_INTERFACE, 'DiscoverableTimeout', dbus.UInt32 (0))
        adapter_properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Pairable', True)
        adapter_properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Alias', hostname)

        try:
            obex.dbus_obj.loop.run()
        except:
            pass


        obex.unregister_obex_agent()
        obex.unregister_agent()

        self.remove_directory_structure ()

if __name__ == '__main__':
    exit(Test().run_test())
