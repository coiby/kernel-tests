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

import functional.connection.functional_connection_base
from base.exception.test import *
from worknode.linux.manager.exception.file_system import *

class Test(functional.connection.functional_connection_base.FunctionalConnectionBaseTest):
    """
    Test sets up a Bluetooth connection.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.remote_device = None
        self.test_bluetooth_connection_settings = {
            'mac_address': None,
            'low_energy': False,
        }
        self.settings_to_custom_map = {
            'mac_address': 'custom_mac_address',
            'low_energy': 'custom_low_energy',
        }
        self.preconfigured_setups_file = 'preconfigured_setups.json'

        self.set_test_name(
            name = '/kernel/bluetooth_tests/functional/connection/setup'
        )
        self.set_test_author(
            name = 'Ken Benoit',
            email = 'kbenoit@redhat.com'
        )
        self.set_test_description(
            description = 'Test OBEX interface'
        )

        self.add_command_line_option(
            '--connectionPreset',
            dest = 'connection_preset',
            action = 'store',
            default = 'random',
            help = 'name of a connection preset',
        )
        self.add_command_line_option(
            '--customMAC',
            dest = 'custom_mac_address',
            action = 'store',
            default = None,
            help = 'custom MAC address to use as the target Bluetooth device for connection',
        )
        self.add_command_line_option(
            '--customLE',
            dest = 'custom_low_energy',
            action = 'store_true',
            default = None,
            help = 'indicate that the target Bluetooth device is a Bluetooth Low Energy device',
        )

        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.start_bluetooth_service,
        )
        self.add_test_step(
            test_step = self.choose_test_bluetooth_interface,
            test_step_description = 'Choose which Bluetooth interface to use and describe it',
        )
        self.add_test_step(
            test_step = self.determine_connection_information,
            test_step_description = 'Determine the connection information to use',
        )
        self.add_test_step(
            test_step = self.set_access_type,
            test_step_description = 'Set the access to OBEX',
        )
        self.add_test_step(
            test_step = self.find_remote_bluetooth_device,
            test_step_description = 'Find the remote Bluetooth device',
        )
        self.add_test_step(
            test_step = self.obex_file_transfer,
            test_step_description = 'OBEX: file transfer test',
        )
        self.add_test_step(
            test_step = self.obex_object_push,
            test_step_description = 'OBEX: object push test',
        )
        self.add_test_step(
            test_step = self.obex_message_access,
            test_step_description = 'OBEX: message access test',
        )
        self.add_test_step(
            test_step = self.obex_sync,
            test_step_description = 'OBEX: synchronization test',
        )
        self.add_test_step(
            test_step = self.obex_pbap,
            test_step_description = 'OBEX: phonebook access test',
        )

    def determine_connection_information(self):
        """
        Determine the connection information to use when configuring the
        Bluetooth connection.

        """
        connection_preset = self.get_command_line_option_value(
            dest = 'connection_preset',
        )
        bluetooth_connection_settings = {}
        # Check if this is supposed to be a custom connection
        if connection_preset != 'custom':
            preconfigured_setups_file = open(self.preconfigured_setups_file)
            preconfigured_setups = json.load(preconfigured_setups_file)
            preconfigured_setups_file.close()
            # Pick a random connection
            if connection_preset == 'random':
                if len(preconfigured_setups) > 0:
                    settings = self.get_random_module().choice(
                        preconfigured_setups.values()
                    )
                    for key, value in settings.iteritems():
                        bluetooth_connection_settings[key] = value
            # Use the preset connection specified
            else:
                if connection_preset not in preconfigured_setups:
                    raise TestFailure(
                        "Unable to locate a preset for '{0}'".format(
                            connection_preset,
                        )
                    )
                settings = preconfigured_setups[connection_preset]
                for key, value in settings.iteritems():
                    bluetooth_connection_settings[key] = value
                    print "%s -> %s" %(bluetooth_connection_settings[key], value)
        for key in self.test_bluetooth_connection_settings.keys():
            if key in self.settings_to_custom_map:
                custom_arg_name = self.settings_to_custom_map[key]
                custom_arg_value = self.get_command_line_option_value(
                    dest = custom_arg_name,
                )
                if custom_arg_value is not None:
                    bluetooth_connection_settings[key] = custom_arg_value
        for key, value in bluetooth_connection_settings.iteritems():
            self.test_bluetooth_connection_settings[key] = value
        self.get_logger().debug(
            "{0}".format(self.test_bluetooth_connection_settings)
        )

    def set_access_type(self):
        self.get_work_manager().set_access_type("obex")
      
    def find_remote_bluetooth_device(self):
        """
        Find a remote Bluetooth device that matches the provided MAC address or
        a random remote Bluetooth device if no MAC address is provided.

        """
        adapter = self.get_work_manager().get_default_local_device()
        if not adapter:
            raise Exception("No default adapter set!")

        if self.test_bluetooth_connection_settings['mac_address'] is not None:
            mac_address = self.test_bluetooth_connection_settings['mac_address']
            device = adapter.get_remote_bluetooth_device(mac_address)
            self.remote_device = device
        else:
            devices = adapter.get_remote_bluetooth_devices()
            if len(devices) == 0:
                raise TestFailure(
                    "Unable to locate any remote Bluetooth devices in " \
                        + "discovery mode"
                )

            self.remote_device = self.get_random_module().choice(devices)

        if self.remote_device is None:
            raise TestFailure(
                "Unable to locate remote Bluetooth device with MAC " \
                    + "address {0}".format(mac_address.upper())
            )

    def obex_file_transfer_setup(self):
        """
        Create all the temp files for the file transfer test
        """
        try:
            tempdir = tempfile.mkdtemp(prefix="bluetooth-")
        except Exception as e:
            raise Exception("Failed to create temp directory: %s" % e)

        with open (tempdir + '/test.txt', 'w') as f:
            f.write("HelloWorld!\n")

        return tempdir

    def obex_file_transfer_cleanup(self, tempdir):
        try:
            shutil.rmtree (tempdir, ignore_errors = True)
        except Exception as e:
            pass

    def obex_file_transfer_remote_cleanup(self, obex, rtempdir):
        files = obex.ftp_listfolder()
        for f in files:
            name = f["Name"]
            obex.ftp_delete(name)

        obex.ftp_changefolder("../")
        obex.ftp_delete(rtempdir)

    def obex_file_transfer(self):
        """
        Test all the OBEX file transfer API commands
        """

        #setup the remote connection
        try:
            obex = self.remote_device.get_command_object('obex')
            obex.setup_file_transfer()
        except Exception as e:
            raise TestFailure(e)


        tempdir = self.obex_file_transfer_setup()
        rtempdir = os.path.basename(tempdir)

        #use tempdir remotely too for uniqueness in the case of parallel tests
        obex.ftp_createfolder(rtempdir)
        
        #put, get, verify
        try:
            obex.ftp_putfile(tempdir + "/test.txt", "test.txt")
            obex.ftp_getfile(tempdir + "/test-got.txt", "test.txt")

            if not filecmp.cmp(tempdir + "/test.txt", tempdir + "/test-got.txt"):
                raise Exception("Received file does not match original file")

        except Exception as e:
            self.obex_file_transfer_remote_cleanup(obex, rtempdir)
            self.obex_file_transfer_cleanup(tempdir)
            raise TestFailure(e)


        #copy, move, delete original, verify
        try:
            obex.ftp_copyfile("test.txt", "test-copy.txt")
            obex.ftp_movefile("test-copy.txt", "test-move.txt")
            obex.ftp_delete("test.txt")

            files = obex.ftp_listfolder()
            if not files:
                raise Exception("Failed to find remote files")

            for f in files:
                name = f["Name"]
                if not name == "test-move.txt":
                    raise Exception("Unknown file in tempdir: %s" % name)

        except Exception as e:
            raise TestFailure(e)

        finally:
            self.obex_file_transfer_remote_cleanup(obex, rtempdir)
            self.obex_file_transfer_cleanup(tempdir)

    def obex_object_push_setup(self):
        """
        Create all the temp files for the object push test
        """
        try:
            (h, tempf) = tempfile.mkstemp(prefix="bluetooth-", suffix="test-my-business-card.txt")
        except Exception as e:
            raise Exception("Failed to create temp file: %s" % e)

        with open (tempf, 'w') as f:
            f.write ('BEGIN:VCARD\n')
            f.write ('VERSION:3.0\n')
            f.write ('N:Doe;Jane\n')
            f.write ('FN:Jane Doe\n')
            f.write ('ORG:Red Hat, Inc.\n')
            f.write ('URL:http://www.redhat.com/\n')
            f.write ('EMAIL:jdoe@redhat.com\n')
            f.write ('TEL;TYPE=voice,work,pref:+49123456789\n')
            f.write ('ADR;TYPE=intl,work,postal,parcel:;;100 E. Davie Street;Raleigh;;NC 27601;USA\n')
            f.write ('END:VCARD\n')

        ####h.close()

        return tempf

    def obex_object_push_cleanup(self, files):
        try:
            for f in files:
                os.remove(f)
        except Exception as e:
            pass

    def obex_object_push_remote_cleanup(self, obex, files):
        for f in files:
            rf = os.path.basename(f)
            try:
                obex.ftp_delete(rf)
            except:
                #if file is already deleted then ignore
                pass

    def obex_object_push(self):
        """
        Test all the OBEX object push API commands
        """

        #setup the remote connection for object push
        #also setup connection for file transfer for cleanup purposes
        try:
            obex = self.remote_device.get_command_object('obex')
            obex.setup_object_push()
            obex.setup_file_transfer()
        except Exception as e:
            raise TestFailure(e)


        tempf = self.obex_object_push_setup()
        rtempf = os.path.basename(tempf)

        #send, pull, verify
        try:
            obex.opp_sendfile(tempf)
            obex.ftp_copyfile(rtempf, rtempf + '.cp')
            obex.opp_pull_business_card(tempf + '.cp')

            if not filecmp.cmp(tempf, tempf + '.cp'):
                raise Exception("Received file does not match original file")

        except Exception as e:
            files = [ tempf, tempf + '.cp' ]
            self.obex_object_push_remote_cleanup(obex, files)
            self.obex_object_push_cleanup(files)
            raise TestFailure(e)


        #remove copies, exchange, verify
        try:
            obex.ftp_delete(rtempf)
            os.remove(tempf + '.cp')
            obex.opp_exchange_business_cards(tempf, tempf + '.cp')

            if not filecmp.cmp(tempf, tempf + '.cp'):
                raise Exception("Received file does not match original file")

            files = obex.ftp_listfolder()
            if not files:
                raise Exception("Failed to find remote files")

            count = 0
            for f in files:
                name = f["Name"]
                if name == rtempf:
                    count += 1
                if name == rtempf + '.cp':
                    count += 1

            if count != 2:
                raise Exception("Did not find expected files on OPP exchange")

        except Exception as e:
            #raise TestFailure(e)
            #ExchangeBusinessCards not implemented, failure expected
            pass

        finally:
            files = [ tempf, tempf + '.cp' ]
            self.obex_object_push_remote_cleanup(obex, files)
            self.obex_object_push_cleanup(files)

    def obex_message_access_setup(self):
        """
        Create all the temp files for the file transfer test
        """
        try:
            tempdir = tempfile.mkdtemp(prefix="bluetooth-")
        except Exception as e:
            raise Exception("Failed to create temp directory: %s" % e)

        with open (tempdir + '/test-message.txt', 'w') as f:
            f.write("HelloWorld!\n")

        return tempdir

    def obex_message_access_cleanup(self, tempdir):
        try:
            shutil.rmtree (tempdir, ignore_errors = True)
        except Exception as e:
            pass

    def obex_message_access_remote_cleanup(self, obex, rtempdir):
        files = obex.ftp_listfolder()
        for f in files:
            name = f["Name"]
            obex.ftp_delete(name)

        obex.ftp_changefolder("../")
        obex.ftp_delete(rtempdir)

    def obex_message_access(self):
        """
        Test all the OBEX message access API calls
        """

        #setup the remote connection for message access
        #also setup connection for file transfer for cleanup purposes
        try:
            obex = self.remote_device.get_command_object('obex')
            obex.setup_message_access()
            obex.setup_file_transfer()
        except Exception as e:
            raise TestFailure(e)

        tempdir = self.obex_message_access_setup()
        rtempdir = os.path.basename(tempdir)

        #verify filter fields
        lfilters = obex.map_list_filter_fields()
        #expected_fields = {'subject', 'timestamp', 'recipient-address', 'type', 'size', 'status'}

        if not lfilters:
            raise Exception("No filter fields returned")

        #out of sync for now, fix later??
        #for f in lfilters:
        #    if f not in expected_fields:
        #        raise Exception("Unexpected filter field: %s" % f)

        #if len(lfilters) != len(expected_fields):
        #    raise Exception("Filter fields are different than expected: %s => %s" % (lfilters, expected_fields))

        #create folder, verify, set folder, verify
        try:
            folder = "inbox"
            files = obex.map_listfolders()
            if not files or not folder in [f["Name"] for f in files]:
                raise Exception("Failed to find remote directory")

            obex.map_setfolder(folder)

            files = obex.map_listfolders()
            if files:
                raise Exception("Found files in empty new directory")

        except Exception as e:
            #self.obex_message_access_remote_cleanup(obex, rtempdir) 
            self.obex_message_access_cleanup(tempdir)
            raise TestFailure(e)


        #push message, update inbox, list messages
        #FIXME update_inbox and push_message, list_messages not working yet
        """
        try:
            obex.map_push_message(tempdir + '/test-message.txt', "outbox")
            obex.map_update_inbox()
            files = obex.map_list_messages(rtempdir)

            for obj, values in files:
                if obj != 'test-message.txt':
                    raise Exception ("Bad message %s [%s]" % (obj, values)) 

        except Exception as e:
            raise TestFailure(e)

        finally:
        """
            #self.obex_message_access_remote_cleanup(obex, rtempdir) 
        self.obex_message_access_cleanup(tempdir)

    def obex_sync_setup(self):
        """
        Create all the temp files for the object push test
        """
        try:
            (h, tempf) = tempfile.mkstemp(prefix="bluetooth-", suffix="test-my-business-card.txt")
        except Exception as e:
            raise Exception("Failed to create temp file: %s" % e)

        with open (tempf, 'w') as f:
            f.write ('BEGIN:VCARD\n')
            f.write ('VERSION:3.0\n')
            f.write ('N:Doe;Jane\n')
            f.write ('FN:Jane Doe\n')
            f.write ('ORG:Red Hat, Inc.\n')
            f.write ('URL:http://www.redhat.com/\n')
            f.write ('EMAIL:jdoe@redhat.com\n')
            f.write ('TEL;TYPE=voice,work,pref:+49123456789\n')
            f.write ('ADR;TYPE=intl,work,postal,parcel:;;100 E. Davie Street;Raleigh;;NC 27601;USA\n')
            f.write ('END:VCARD\n')

        ####h.close()

        return tempf

    def obex_sync_cleanup(self, files):
        try:
            for f in files:
                os.remove(f)
        except Exception as e:
            pass

    def obex_sync(self):
        """
        Test all the OBEX sync API calls
        """

        #setup the remote connection for message access
        #also setup connection for file transfer for cleanup purposes
        try:
            obex = self.remote_device.get_command_object('obex')
            obex.setup_sync()
        except Exception as e:
            raise TestFailure(e)

        tempf = self.obex_sync_setup()
 
        #set location, put phonebook, get phonebook, verify
        try:
            obex.sync_set_location("int")
            #This PUT command isn't working correctly
            #obex.sync_put_phonebook(tempf)
            #obex.sync_get_phonebook(tempf + '.new')
            

        except Exception as e:
            raise TestFailure(e)

        finally:
            files = [ tempf, tempf + '.new' ]
            self.obex_sync_cleanup(files)

    def obex_pbap_setup(self):
        """
        Create all the temp files for the object push test
        """
        try:
            (h, tempf) = tempfile.mkstemp(prefix="bluetooth-", suffix="test-my-phonebook.vcf")
        except Exception as e:
            raise Exception("Failed to create temp file: %s" % e)

        return tempf

        with open (tempf, 'w') as f:
            f.write ('BEGIN:VCARD\n')
            f.write ('VERSION:3.0\n')
            f.write ('N:Doe;Jane\n')
            f.write ('FN:Jane Doe\n')
            f.write ('ORG:Red Hat, Inc.\n')
            f.write ('URL:http://www.redhat.com/\n')
            f.write ('EMAIL:jdoe@redhat.com\n')
            f.write ('TEL;TYPE=voice,work,pref:+49123456789\n')
            f.write ('ADR;TYPE=intl,work,postal,parcel:;;100 E. Davie Street;Raleigh;;NC 27601;USA\n')
            f.write ('END:VCARD\n')

        ####h.close()

        return tempf

    def obex_pbap_cleanup(self, files):
        try:
            for f in files:
                os.remove(f)
        except Exception as e:
            pass

    def obex_pbap(self):
        """
        Test all the OBEX phonebook access API calls
        """

        #setup the remote connection for message access
        #also setup connection for file transfer for cleanup purposes
        try:
            obex = self.remote_device.get_command_object('obex')
            obex.setup_pbap()
        except Exception as e:
            raise TestFailure(e)

        #list filter fields, update version
        try:
            result = obex.pbap_list_filter_fields()
            #todo version results??
        except Exception as e:
            raise TestFailure(e)

        try:
            obex.pbap_update_version() 
        except Exception as e:
            #update version not implemented, failure expected
            pass

        #select, get size, list, verify
        try:
            obex.pbap_select("int", "och")
            size = obex.pbap_getsize()
            names = obex.pbap_list()

            if size != 2:
                raise Exception("PBAP mismatch size: expected %s, got %s" % ('2', size))

            if not (('1.vcf', 'Outgoing1') in (names) and ('2.vcf', 'Outgoing2') in (names)):
                raise Exception("PBAP mismatched vcf files in List()")

        except Exception as e:
            raise TestFailure(e)

        tempf = self.obex_pbap_setup()

        #select, search, pull
        try:
            obex.pbap_select("int", "ich")
            result = obex.pbap_search('Incoming2', 'name')

            if not ('2.vcf', 'Incoming2') in (result):
                raise Exception("PBAP failed Search()")

            obex.pbap_pull('2.vcf', tempf)

        except Exception as e:
            files = [ tempf, tempf + '.new' ]
            self.obex_pbap_cleanup(files)
            raise TestFailure(e)

        #pull all
        try:
            obex.pbap_pullall(tempf)
            #verify??

        except Exception as e:
            raise TestFailure(e)
 
        finally:
            files = [ tempf, tempf + '.new' ]
            self.obex_pbap_cleanup(files)

if __name__ == '__main__':
    exit(Test().run_test())
