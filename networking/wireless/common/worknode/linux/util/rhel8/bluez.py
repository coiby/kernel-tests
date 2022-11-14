#!/usr/bin/python
# Copyright (c) 2018 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.util.rhel8.bluez module provides a class
(bluez) that represents the bluez command line executable.

"""

__author__ = 'Ken Benoit'

import time
import dbus.mainloop.glib
import dbus.service
import dbus
import time
import subprocess
import os

from gi.repository import GObject
from gi.repository import GLib

import worknode.linux.util.bluez
from worknode.exception.worknode_executable import *


BLUEZ_SERVICE = "org.bluez"

BLUEZ_ADAPTER_INTERFACE = "org.bluez.Adapter1"
BLUEZ_DEVICE_INTERFACE = "org.bluez.Device1"
FREEDESKTOP_DBUS_OBJECT_MANAGER = 'org.freedesktop.DBus.ObjectManager'

class BluezDBus(object):
    def __init__(self):
        try:
            dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
            self.loop = GObject.MainLoop ()
            self.session_bus = self.__launch_session_bus()
            self.system_bus = dbus.SystemBus()
        except Exception as e:
            raise Exception("BluezDBus: {0}".format(e))

    def __launch_session_bus (self):
        try:
            session_bus = dbus.SessionBus ()
        except Exception as e:
            # Don't run this using 'su', otherwise this session bus won't be picked up by this test (dbus checks for setuid)
            session_bus_process = subprocess.Popen('dbus-launch --exit-with-session',
                                                   shell = True,
                                                   stdout = subprocess.PIPE,
                                                   stderr = subprocess.STDOUT)
            for var in session_bus_process.stdout:
                sp = var.split ('=', 1)
                os.environ[sp[0]] = sp[1][:-1]

            #connect to our newly created SessionBus
            try:
                session_bus = dbus.bus.BusConnection(os.environ["DBUS_SESSION_BUS_ADDRESS"])
            except Exception as e:
                raise Exception("Can't create local D-Bus session")
                session_bus = ""

        return session_bus

    def add_properties_changed_cb(self, cb):
        self.session_bus.add_signal_receiver(cb,
                                             signal_name = 'PropertiesChanged',
                                             path_keyword = "path")

    def add_interfaces_removed_cb(self, cb):
        self.session_bus.add_signal_receiver(cb,
                                             signal_name = 'InterfacesRemoved',
                                             path_keyword = "path")

class bluez(worknode.linux.util.bluez.bluez):
    """
    bluez represents the bluez command line executable, which
    provides an interactive command line utility for configuring local and
    remote Bluetooth devices.

    """
    def __init__(self, work_node, dbus_obj = None, device = None):
        super(bluez, self).__init__(
            work_node = work_node,
        )
        self.transfer_path = None
        self.adapter = None
        self.adapter_properties = None

        if not dbus_obj:
            dbus_obj = BluezDBus()
        else:
            dbus_obj.add_properties_changed_cb(self.__properties_changed_cb)
            dbus_obj.add_interfaces_removed_cb(self.__interfaces_removed_cb)

        self.dbus_obj = dbus_obj
        self.device = device

    def __interfaces_removed_cb(self, object_path, interfaces, path):
        """
        Generic InterfacesRemoved callback.
        Set self.transfer_path to match passed object
        Will set self.interfaces_removed to True on match
        """

        if object_path == self.transfer_path:
            self.interfaces_removed = True

    def __properties_changed_cb (self, interface_name, properties, invalidated_properties, path):
        """
        Generic PropertiesChanged callback.
        Set self.transfer_path to match passed object
        Will set self.properites_changed to True on match
        """
        if path != self.transfer_path:
            return

        if "Status" in properties and \
                      (properties["Status"] == "complete" or \
                       properties["Status"] == "error"):
            self.properties_changed = True

            if properties["Status"] == "complete":
                self.properties_changed_success = True
            else:
                self.properties_changed_success = False

            self.dbus_obj.loop.quit()
            return

        if "Transferred" not in properties:
            return

    def create_transfer_reply(self, path, properties):
        self.properties_changed_success = False
        self.transfer_path = path
        self.transfer_error = None
        self.props[path] = properties
        #print ("Transfer created: %s :: %s" % (path, self.transfer_path))

    def generic_reply(self):
        self.properties_changed_success = True
        self.transfer_error = None
        self.dbus_obj.loop.quit()
        #print ("Transfer succeeded")

    def error(self, err):
        self.properties_changed_success = False
        self.transfer_error = err
        #print ("Transfer error: %s" % err)
        self.dbus_obj.loop.quit()

    def transfer_finish(self, err_msg, target=None):
        if self.transfer_error or \
           (target and not os.path.isfile( target )) or \
            not self.properties_changed_success:

            if self.transfer_error:
                msg = self.transfer_error
            elif target and not os.path.isfile(target):
                msg = "missing {0}".format(target)
            else:
                msg = "transfer not successful"

            raise Exception("Failed: {0} ({1})".format(err_msg, msg))

    def find_controllers(self, mac_address = None):
        controller_list = []
        try:
            bus = self.dbus_obj.system_bus
            bluez = bus.get_object (BLUEZ_SERVICE, '/')
            bluez_manager = dbus.Interface (bluez, FREEDESKTOP_DBUS_OBJECT_MANAGER)
            objects = bluez_manager.GetManagedObjects ()

            for path in objects:
                if (BLUEZ_ADAPTER_INTERFACE in objects[path].keys ()):
                    adapter = dbus.Interface(bus.get_object(BLUEZ_SERVICE, path), BLUEZ_ADAPTER_INTERFACE)
                    properties = objects[path][BLUEZ_ADAPTER_INTERFACE]
                    if not mac_address or properties['Address'] == mac_address:
                        controller_list.append((adapter, properties))

        except Exception as e:
            raise Exception ("List local controllers: {0}".format(str(e)))

        if not controller_list:
            return (None, None)

        return controller_list

    def list_controllers(self):
        """
        Get a list of local Bluetooth controllers.

        Return value:
        List of dictionaries describing the local Bluetooth controllers.

        """
        controller_list = []

        controllers = self.find_controllers()

        for controller, properties in controllers:
            controller_list.append({ 'mac_address' : str(properties['Address']),
                                     'name'        : str(properties['Name']),
                                     'device'      : controller,
                                   } )

        return controller_list

    def find_remote_device(self, mac_address):
        """
        Get a remote Bluetooth device

        Uses mac_address as lookup key

        Return value:
        The device is found
        """
        device_list = []

        try:
            bus = self.dbus_obj.system_bus
            bluez = bus.get_object (BLUEZ_SERVICE, '/')
            bluez_manager = dbus.Interface (bluez, FREEDESKTOP_DBUS_OBJECT_MANAGER)
            objects = bluez_manager.GetManagedObjects ()
            for path, interfaces in objects.items():
                if (BLUEZ_DEVICE_INTERFACE in interfaces.keys () and 'Name' in interfaces[BLUEZ_DEVICE_INTERFACE]):
                    device  = dbus.Interface(bus.get_object(BLUEZ_SERVICE, path), BLUEZ_DEVICE_INTERFACE)
                    properties = interfaces[BLUEZ_DEVICE_INTERFACE]
                    if mac_address == str(properties['Address']):
                        return ({ 'mac_address' : str(properties['Address']),
                                  'name'        : str(properties['Name']),
                                  'device'      : device,
                                } )

        except Exception as e:
            raise Exception('Find remote devices: {0}'.format(str(e)))

        return device_list

    def __list_remote_devices(self, mac_address = None):
        device_list = []

        try:
            bus = self.dbus_obj.system_bus
            bluez = bus.get_object (BLUEZ_SERVICE, '/')
            bluez_manager = dbus.Interface (bluez, FREEDESKTOP_DBUS_OBJECT_MANAGER)
            objects = bluez_manager.GetManagedObjects ()
            for path, interfaces in objects.items():
                if (BLUEZ_DEVICE_INTERFACE in interfaces.keys () and 'Name' in interfaces[BLUEZ_DEVICE_INTERFACE]):
                    device  = dbus.Interface(bus.get_object(BLUEZ_SERVICE, path), BLUEZ_DEVICE_INTERFACE)
                    properties = interfaces[BLUEZ_DEVICE_INTERFACE]
                    obj = ({ 'mac_address' : str(properties['Address']),
                             'name'        : str(properties['Name']),
                             'alias'       : str(properties['Alias']),
                             'device'      : device,
                           } )
                    if mac_address:
                        mac = mac_address.upper()
                        if mac  == str(properties['Address']).upper():
                            return [obj]
                        if mac  == str(properties['Name']).upper():
                            return [obj]
                        if mac  == str(properties['Alias']).upper():
                            return [obj]

                    device_list.append(obj)

        except Exception as e:
            raise Exception('List remote devices: {0}'.format(str(e)))

        if not mac_address:
            return device_list

        return None

    def list_remote_devices(self):
        """
        Get a list of remote Bluetooth devices.

        Return value:
        List of dictionaries describing the remote Bluetooth devices.

        """
        if not self.adapter:
            raise Exception("Set local controller")

        self.adapter.StartDiscovery ()
        time.sleep (10)
        #time.sleep (1)
        self.adapter.StopDiscovery ()

        return self.__list_remote_devices()

    def get_remote_device(self, mac_address):
        """
        Get a specific remote Bluetooth device

        mac_address: address of remote device

        Return value:
        an object containing the remote device
        """
        device_list = self.__list_remote_devices(mac_address = mac_address)

        if device_list:
            #should only be one match in array
            return device_list[0]

        if not self.adapter:
            raise Exception("Set local controller")

        #Not in cache, let's probe
        self.adapter.StartDiscovery ()
        time.sleep (10)
        self.adapter.StopDiscovery ()

        device_list = self.__list_remote_devices(mac_address = mac_address)

        if device_list:
            return device_list[0]

        return None

    def set_as_default(self, mac_address):
        """
        Set the provided Bluetooth controller's MAC address as the default
        Bluetooth controller.

        Keyword arguments:
        mac_address - MAC address of the Bluetooth controller to set as the
                      default.

        """
        controllers = self.find_controllers(mac_address = mac_address)
        if not controllers or len(controllers) > 1:
            raise Exception("No exact match for mac_address: {0}".format(mac_address))

        (self.adapter, self.adapter_properties) = controllers[0]

    def turn_power_on(self):
        """
        Turn the power on on the default Bluetooth controller.

        """
        properties = dbus.Interface (self.adapter, dbus.PROPERTIES_IFACE)
        properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Powered', True)

    def turn_power_off(self):
        """
        Turn the power off on the default Bluetooth controller.

        """
        properties = dbus.Interface (self.adapter, dbus.PROPERTIES_IFACE)
        properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Powered', False)

    def start_agent(self):
        """
        Start the pairing agent on the default Bluetooth controller.

        """
        print("TODO: start_agent")

    def stop_agent(self):
        """
        Stop the pairing agent on the default Bluetooth controller.

        """
        print("TODO: stop_agent")

    def enable_default_agent(self):
        """
        Enable the default pairing agent on the default Bluetooth controller.

        """
        print("TODO: enable_default_agent")

    def enable_pairing(self):
        """
        Enable pairing on the default Bluetooth controller.

        """
        properties = dbus.Interface (self.adapter, dbus.PROPERTIES_IFACE)
        properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Pairable', True)

    def disable_pairing(self):
        """
        Disable pairing on the default Bluetooth controller.

        """
        properties = dbus.Interface (self.adapter, dbus.PROPERTIES_IFACE)
        properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Pairable', False)

    def start_scanning(self):
        """
        Start scanning mode on the default Bluetooth controller.

        """
        self.adapter.StartDiscovery()

    def stop_scanning(self):
        """
        Stop scanning mode on the default Bluetooth controller.

        """
        self.adapter.StopDiscovery()

    def enable_discovery_mode(self):
        """
        Enable discovery mode on the default Bluetooth controller.

        """
        properties = dbus.Interface (self.adapter, dbus.PROPERTIES_IFACE)
        properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Discoverable', True)

    def disable_discovery_mode(self):
        """
        Disable discovery mode on the default Bluetooth controller.

        """
        properties = dbus.Interface (self.adapter, dbus.PROPERTIES_IFACE)
        properties.Set (BLUEZ_ADAPTER_INTERFACE, 'Discoverable', False)

    def pair_remote_device(self, mac_address):
        """
        Perform the pairing process with the remote Bluetooth device.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to pair with.

        """
        print("TODO: pair_remote_device()")

    def trust_remote_device(self, mac_address):
        """
        Trust the remote Bluetooth device in order to allow the remote device to
        reconnect itself.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to trust.

        """
        print("TODO: trust_remote_device")

    def untrust_remote_device(self, mac_address):
        """
        Untrust the remote Bluetooth device in order to disallow the remote
        device to reconnect itself.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to untrust.

        """
        print("TODO: untrust_remote_device")

    def remove_remote_device(self, mac_address):
        """
        Remove the remote Bluetooth device from the list of paired devices.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to remove.

        """
        print("TODO: remove_remote_device")

    def connect_remote_device(self, mac_address):
        """
        Connect to the remote Bluetooth device that was previously paired.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to connect to.

        """
        try:
            self.device.Connect()
        except Exception as e:
            raise Exception(
                "Unable to connect to Bluetooth device {mac_address}".format(
                    mac_address = mac_address
                )
            )

    def disconnect_remote_device(self, mac_address):
        """
        Disconnect from the remote Bluetooth device that was previously paired.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to disconnect
                      from.

        """
        try:
            self.device.Disconnect()
        except Exception as e:
            raise Exception(
                "Unable to disconnect from Bluetooth device" + \
                    " {mac_address}".format(
                        mac_address = mac_address
                    )
            )

    def block_remote_device(self, mac_address):
        """
        Add the remote Bluetooth device to the blacklist.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to add to the
                      blacklist.

        """
        print("TODO: block_remote_device")

    def unblock_remote_device(self, mac_address):
        """
        Remove the remote Bluetooth devices from the blacklist.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to remove from
                      the blacklist.

        """
        print("TODO: unblock_remote_device")

    def is_paired(self, mac_address):
        """
        Check if the remote Bluetooth device is paired.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is paired. False if device isn't paired.

        """
        print("TODO: is_paired")

    def is_trusted(self, mac_address):
        """
        Check if the remote Bluetooth device is trusted.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is trusted. False if device isn't trusted.

        """
        print("TODO: is_trusted")

    def is_blocked(self, mac_address):
        """
        Check if the remote Bluetooth device is blocked.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is blocked. False if device isn't blocked.

        """
        blocked = False

        obj = dbus.Interface(self.device, dbus.PROPERTIES_IFACE)
        properties = obj.GetAll(BLUEZ_DEVICE_INTERFACE)

        if properties['Blocked']:
            blocked = True

        return blocked

    def is_connected(self, mac_address):
        """
        Check if the remote Bluetooth device is connected.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is connected. False if device isn't connected.

        """
        connected = False

        obj = dbus.Interface(self.device, dbus.PROPERTIES_IFACE)
        properties = obj.GetAll(BLUEZ_DEVICE_INTERFACE)

        if properties['Connected']:
            connected = True

        return connected

    def is_powered(self, mac_address):
        """
        Get the power state of the Bluetooth controller requested.

        Return value:
        True if the Bluetooth controller is powered. False if it isn't.

        """
        obj = dbus.Interface(self.adapter, dbus.PROPERTIES_IFACE)
        properties = obj.GetAll(BLUEZ_ADAPTER_INTERFACE)

        return properties['Powered']

    def is_pairable(self, mac_address):
        """
        Check if the remote Bluetooth device is connected.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is connected. False if device isn't connected.

        """
        obj = dbus.Interface(self.adapter, dbus.PROPERTIES_IFACE)
        properties = obj.GetAll(BLUEZ_ADAPTER_INTERFACE)

        return properties['Pairable']
