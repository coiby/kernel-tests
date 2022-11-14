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
The worknode.linux.util.rhel7.bluez module provides a class
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
import worknode.linux.util.rhel7.bluez
from worknode.exception.worknode_executable import *

BLUEZ_DEVICE_INTERFACE = "org.bluez.Device1"

BLUEZ_SERVICE = "org.bluez"
BLUEZ_OBEX_SERVICE = "org.bluez.obex"
BLUEZ_OBEX_PATH = "/org/bluez/obex"
BLUEZ_OBEX_CLIENT_INTERFACE = "org.bluez.obex.Client1"
BLUEZ_OBEX_TRANSFER_INTERFACE = "org.bluez.obex.Transfer1"
BLUEZ_OBEX_FILE_TRANSFER_INTERFACE = "org.bluez.obex.FileTransfer1"
BLUEZ_OBEX_OBJECT_PUSH_INTERFACE = "org.bluez.obex.ObjectPush1"
BLUEZ_OBEX_PHONEBOOK_ACCESS_INTERFACE = "org.bluez.obex.PhonebookAccess1"
BLUEZ_OBEX_MESSAGE_ACCESS_INTERFACE = "org.bluez.obex.MessageAccess1"
BLUEZ_OBEX_SYNC_INTERFACE = "org.bluez.obex.Synchronization1"

FREEDESKTOP_DBUS_OBJECT_MANAGER = 'org.freedesktop.DBus.ObjectManager'
BLUEZ_AGENT_MANAGER_INTERFACE = 'org.bluez.AgentManager1'
BLUEZ_OBEX_AGENT_MANAGER_INTERFACE = 'org.bluez.obex.AgentManager1'

OBJECT_PUSH_UUID =      '00001105-0000-1000-8000-00805f9b34fb'
FILE_TRANSFER_UUID =    '00001106-0000-1000-8000-00805f9b34fb'
PHONEBOOK_ACCESS_UUID = '0000112f-0000-1000-8000-00805f9b34fb'
MESSAGE_ACCESS_UUID =   '00001133-0000-1000-8000-00805f9b34fb'
SYNC_UUID =             '00001104-0000-1000-8000-00805f9b34fb'


class obex(worknode.linux.util.rhel7.bluez.bluez):
    """
    bluez represents the bluez command line executable, which
    provides an interactive command line utility for configuring local and
    remote Bluetooth devices.

    """
    def __init__(self, work_node, dbus_obj = None, device = None, mac_address = None):
        super(obex, self).__init__(
            work_node = work_node,
            dbus_obj = dbus_obj,
            device = device
        )

        if not dbus_obj:
            dbus_obj = self.dbus_obj

        session = dbus_obj.session_bus.get_object(BLUEZ_OBEX_SERVICE, BLUEZ_OBEX_PATH)
        interface = dbus.Interface(session, BLUEZ_OBEX_CLIENT_INTERFACE)
        self.obex = interface
        self.mac_address = mac_address
        self.transfer_path = None
        self.props = {}
        self.ftp = None
        self.opp = None
        self.mahp = None
        self.sync = None
        self.pbap = None

    def setup_file_transfer(self):
        """
        Setup the OBEX ftp session
        """
        if self.ftp:
            return

        iface = dbus.Interface(self.device, dbus.PROPERTIES_IFACE)
        prop = iface.GetAll(BLUEZ_DEVICE_INTERFACE)

        if not FILE_TRANSFER_UUID in prop["UUIDs"]:
            raise Exception("Remote device does not support file transfer")

        session = self.obex.CreateSession(self.mac_address, {'Target':'ftp'})
        obj = self.dbus_obj.session_bus.get_object(BLUEZ_OBEX_SERVICE, session)
        ftp = dbus.Interface(obj, BLUEZ_OBEX_FILE_TRANSFER_INTERFACE)

        if not ftp:
            raise Excpetion("Could not setup remote file transfer")

        self.ftp = ftp

    def ftp_changefolder(self, folder):
        self.ftp.ChangeFolder(folder)

    def ftp_createfolder(self, folder):
        self.ftp.CreateFolder(folder)

    def ftp_listfolder(self):
        return self.ftp.ListFolder()

    def ftp_getfile(self, target, source):

        self.ftp.GetFile(target, source,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("GET file", target=target)

    def ftp_putfile(self, source, target):
        if not os.path.isfile( source ):
            raise Exception("%s does not exist" % source)

        self.ftp.PutFile(source, target,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("PUT file")

    def ftp_copyfile(self, source, target):
        self.ftp.CopyFile(source, target,
                    reply_handler=self.generic_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("COPY file")

    def ftp_movefile(self, source, target):
        self.ftp.MoveFile(source, target,
                    reply_handler=self.generic_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("MOVE file")

    def ftp_delete(self, filename):
        self.ftp.Delete(filename,
                    reply_handler=self.generic_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("DELETE file")

    def setup_object_push(self):
        """
        Setup the OBEX object push
        """
        if self.opp:
            return

        iface = dbus.Interface(self.device, dbus.PROPERTIES_IFACE)
        prop = iface.GetAll(BLUEZ_DEVICE_INTERFACE)

        if not OBJECT_PUSH_UUID in prop["UUIDs"]:
            raise Exception("Remote device does not support object push")

        session = self.obex.CreateSession(self.mac_address, {'Target':'opp'})
        obj = self.dbus_obj.session_bus.get_object(BLUEZ_OBEX_SERVICE, session)
        opp = dbus.Interface(obj, BLUEZ_OBEX_OBJECT_PUSH_INTERFACE)

        if not opp:
            raise Excpetion("Could not setup remote object push")

        self.opp = opp

    def opp_sendfile(self, source):
        if not os.path.isfile( source ):
            raise Exception("%s does not exist" % source)

        self.opp.SendFile(source,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("SEND file")

    def opp_pull_business_card(self, target):

        self.opp.PullBusinessCard(target,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("PULL card", target=target)

    def opp_exchange_business_cards(self, source, target):
        if not os.path.isfile( source ):
            raise Exception("%s does not exist" % source)

        self.opp.ExchangeBusinessCards(source, target,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("EXCHANGE card", target=target)

    def setup_message_access(self):
        """
        Setup the OBEX message access
        """
        if self.mahp:
            return

        iface = dbus.Interface(self.device, dbus.PROPERTIES_IFACE)
        prop = iface.GetAll(BLUEZ_DEVICE_INTERFACE)

        if not MESSAGE_ACCESS_UUID in prop["UUIDs"]:
            raise Exception("Remote device does not support message access")

        session = self.obex.CreateSession(self.mac_address, {'Target':'map'})
        obj = self.dbus_obj.session_bus.get_object(BLUEZ_OBEX_SERVICE, session)
        mahp = dbus.Interface(obj, BLUEZ_OBEX_MESSAGE_ACCESS_INTERFACE)

        if not mahp:
            raise Exception("Could not setup remote object push")

        self.mahp = mahp

    def map_setfolder(self, folder):
        self.mahp.SetFolder(folder)

    def map_listfolders(self, lfilter={}):
        filter_list = { 'Offset', 'MaxCount' }

        for k in lfilter:
            if k not in filter_list:
                raise Exception ('Bad keyword in filter: %s' % k)

        return self.mahp.ListFolders(lfilter)

    def map_list_filter_fields(self):
        return self.mahp.ListFilterFields()

    def map_list_messages(self, folder, lfilter={}):
        filter_list = { 'Offset', 'MaxCount', 'SubjectLength',
                        'Fields', 'Type', 'PeriodStart', 'PeriodEnd',
                        'Status', 'Recipient', 'Sender', 'Priority'
                      }

        for k in lfilter:
            if k not in filter_list:
                raise Exception ('Bad keyword in filter: %s' % k)

        return self.mahp.ListMessages(folder, lfilter)

    def map_push_message(self, source, folder, args=dict()):
        args_list = { 'Transparent', 'Retry', 'Charset' }

        for a in args:
            if a not in args_list:
                raise Exception ('Bad arg: %s' % a)

        if not os.path.isfile( source ):
            raise Exception("%s does not exist" % source)

        self.mahp.PushMessage(source, folder, args,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("Push Message")

    def map_update_inbox(self):
        return self.mahp.UpdateInbox()

    def setup_sync(self):
        """
        Setup the OBEX synchronization
        """
        if self.sync:
            return

        iface = dbus.Interface(self.device, dbus.PROPERTIES_IFACE)
        prop = iface.GetAll(BLUEZ_DEVICE_INTERFACE)

        if not SYNC_UUID in prop["UUIDs"]:
            raise Exception("Remote device does not support synchronization")

        session = self.obex.CreateSession(self.mac_address, {'Target':'sync'})
        obj = self.dbus_obj.session_bus.get_object(BLUEZ_OBEX_SERVICE, session)
        sync = dbus.Interface(obj, BLUEZ_OBEX_SYNC_INTERFACE)

        if not sync:
            raise Exception("Could not setup remote sync")

        self.sync = sync

    def sync_set_location(self, location):
        """
        Location is where the phonebook is stored: int, sim1, sim2, ...
        """
        self.sync.SetLocation(location)

    def sync_get_phonebook(self, target):
        self.sync.GetPhonebook(target,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("GET Phonebook", target=target)

    def sync_put_phonebook(self, source):
        if not os.path.isfile( source ):
            raise Exception("%s does not exist" % source)

        self.sync.PutPhonebook(source,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("PUT Phonebook")

    def setup_pbap(self):
        """
        Setup the OBEX Phonebook Access profile
        """
        if self.pbap:
            return

        iface = dbus.Interface(self.device, dbus.PROPERTIES_IFACE)
        prop = iface.GetAll(BLUEZ_DEVICE_INTERFACE)

        if not PHONEBOOK_ACCESS_UUID in prop["UUIDs"]:
            raise Exception("Remote device does not support phonebook access")

        session = self.obex.CreateSession(self.mac_address, {'Target':'pbap'})
        obj = self.dbus_obj.session_bus.get_object(BLUEZ_OBEX_SERVICE, session)
        pbap = dbus.Interface(obj, BLUEZ_OBEX_PHONEBOOK_ACCESS_INTERFACE)

        if not pbap:
            raise Exception("Could not setup remote phonebook access")

        self.pbap = pbap

    def pbap_select(self, location, phonebook):
        """
        Location is where the phonebook is stored: int, sim1, sim2, ...
        Phonebook is they type: 'pb', 'ich', 'och', 'mch', ...
        """
        self.pbap.Select(location, phonebook)

    def pbap_pullall(self, target, filters={}):
        self.pbap.PullAll(target, filters,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("PULLALL Phonebook", target=target)

    def pbap_list(self, filters={}):
        return self.pbap.List(filters)

    def pbap_pull(self, vcard, target, filters={}):
        #if os.path.isfile( target ):
        #    raise Exception("Failed to Pull Phonebook %s, file exists" % target)

        self.pbap.Pull(vcard, target, filters,
                    reply_handler=self.create_transfer_reply,
                    error_handler=self.error)

        self.dbus_obj.loop.run()

        self.transfer_finish("PULL Phone card", target=target)

    def pbap_search(self, value, field="name", filters={}):
        return self.pbap.Search(field, value, filters)

    def pbap_getsize(self):
        return self.pbap.GetSize()

    def pbap_update_version(self):
        return self.pbap.UpdateVersion()

    def pbap_list_filter_fields(self):
        return self.pbap.ListFilterFields()

    def register_agent(self, path, security='NoInputNoOutput', default=True):
        system_bus = self.dbus_obj.system_bus
        obj = system_bus.get_object(BLUEZ_SERVICE, '/org/bluez')
        manager = dbus.Interface(obj, BLUEZ_AGENT_MANAGER_INTERFACE)

        manager.RegisterAgent(path, security)

        if default:
            manager.RequestDefaultAgent(path)

        self.agent_path = path

    def unregister_agent(self):
        system_bus = self.dbus_obj.system_bus
        obj = system_bus.get_object(BLUEZ_SERVICE, '/org/bluez')
        manager = dbus.Interface(obj, BLUEZ_AGENT_MANAGER_INTERFACE)

        manager.UnregisterAgent(self.agent_path)

    def register_obex_agent(self, path):
        session_bus = self.dbus_obj.session_bus
        obj = session_bus.get_object(BLUEZ_OBEX_SERVICE, '/org/bluez/obex')
        manager = dbus.Interface(obj, BLUEZ_OBEX_AGENT_MANAGER_INTERFACE)

        session_bus.activate_name_owner ('org.bluez.obex')
        manager.RegisterAgent(path)

        self.obex_agent_path = path

    def unregister_obex_agent(self):
        session_bus = self.dbus_obj.session_bus
        print("step1")
        obj = session_bus.get_object(BLUEZ_OBEX_SERVICE, '/org/bluez/obex')
        print("step2")
        manager = dbus.Interface(obj, BLUEZ_OBEX_AGENT_MANAGER_INTERFACE)

        manager.UnregisterAgent(self.obex_agent_path)
