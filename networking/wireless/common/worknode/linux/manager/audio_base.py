#!/usr/bin/python
# Copyright (c) 2014 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.manager.audio_base module provides a class (AudioManager)
that manages all audio-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_component_manager
import framework
import worknode.property_manager
from worknode.exception.worknode_executable import *
from constants.time import *

class AudioManager(worknode.worknode_component_manager.WorkNodeComponentManager):
    """
    AudioManager is an object that manages all audio-related activities. It
    acts as a container for audio-related commands as well as being a unified
    place to request abstracted audio information from and control the sound
    card audio from.

    """
    def __init__(self, parent):
        super(AudioManager, self).__init__(parent = parent)
        self.__soundcards = {}
        self.__unsupported_soundcards = []
        self.__property_manager = worknode.property_manager.PropertyManager(
            work_node = self._get_work_node(),
        )
        self.__initialize_property_manager()

    def __initialize_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'soundcard_index')
        property_manager.initialize_property(property_name = 'soundcard_pciid')

    def _create_soundcard(self, index):
        raise NotImplementedError

    def get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def discover_soundcards(self):
        """
        Discover all of the soundcards present on the work node.

        """
        self.get_property_manager().refresh_properties()
        soundcard_indices = self.get_property_manager().get_property_value(
            property_name = 'soundcard_index',
        )
        self.__clear_soundcard_list()
        if soundcard_indices is not None:
            for index in soundcard_indices:
                self._create_soundcard(index = index)

    def discover_unsupported_soundcards(self):
        """
        Attempt to locate soundcards that are present on the work node but are
        not currently supported by the OS fully.

        """
        self.discover_soundcards()
        soundcard_pciids = self.get_property_manager().get_property_value(
            property_name = 'soundcard_pciid',
        )
        soundcards = self.get_soundcards()
        for soundcard_pciid in soundcard_pciids:
            found_matching_card = False
            for soundcard in soundcards:
                vendor_id = soundcard.get_vendor_id()
                device_id = soundcard.get_device_id()
                id_string = '{vendor_id}:{device_id}'.format(
                    vendor_id = vendor_id[2:],
                    device_id = device_id[2:],
                )
                if soundcard_pciid == id_string:
                    found_matching_card = True
                    break
            if not found_matching_card:
                self.__unsupported_soundcards.append(soundcard_pciid)

    def _add_soundcard(self, soundcard_object):
        """
        Add a soundcard object to the manager.

        Keyword arguments:
        soundcard_object - Soundcard object.

        """
        self.__soundcards[int(soundcard_object.get_index())] = soundcard_object

    def __clear_soundcard_list(self):
        """
        Clear the manager's list of cached Soundcard objects.

        """
        for soundcard in list(self.__soundcards.values()):
            del soundcard
        for key in list(self.__soundcards.keys()):
            del self.__soundcards[key]

    def get_soundcard(self, index):
        """
        Get the specified soundcard object.

        Keyword arguments:
        index - Index number of the soundcard to return.

        Return value:
        Soundcard object.

        """
        index = int(index)
        if index not in self.__soundcards:
            self.discover_soundcards()
        return self.__soundcards[index]

    def get_soundcards(self):
        """
        Get a list of all soundcard objects.

        Return value:
        List of Soundcard objects.

        """
        if list(self.__soundcards.values()) == []:
            self.discover_soundcards()
        return list(self.__soundcards.values())

    def get_unsupported_soundcard_ids(self):
        """
        Get a list of PCI/USB IDs of soundcards present in the work node but are
        not currently supported by the OS.

        """
        if self.__unsupported_soundcards == []:
            self.discover_unsupported_soundcards()
        return self.__unsupported_soundcards

    def __del__(self):
        self.__clear_soundcard_list()
        super(AudioManager, self).__del__()

class Soundcard(framework.Framework):
    """
    Base class for different types of soundcards to inherit from.

    """
    def __init__(self, parent, index):
        super(Soundcard, self).__init__()
        self.__parent = parent
        self.__property_manager = worknode.property_manager.PropertyManager(
            work_node = self._get_work_node(),
        )
        self.__index = int(index)
        self.__controls = {}
        self.__commands = {}
        self.__soundcard_control_factory = None
        self.__card_type = ""
        self.__card_name = ""
        self.__initialize_property_manager()

    def __initialize_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'id')
        property_manager.initialize_property(property_name = 'name')
        property_manager.initialize_property(property_name = 'vendor_id')
        property_manager.initialize_property(property_name = 'device_id')
        property_manager.initialize_property(
            property_name = 'subsystem_vendor_id',
        )
        property_manager.initialize_property(
            property_name = 'subsystem_device_id',
        )
        property_manager.initialize_property(property_name = 'card_type')
        property_manager.initialize_property(property_name = 'card_name')
        property_manager.initialize_property(property_name = 'mixer_name')
        property_manager.initialize_property(property_name = 'components')
        property_manager.initialize_property(property_name = 'number_of_controls')
        property_manager.initialize_property(property_name = 'number_of_simple_controls')

    def add_command(self, command_name, command_object):
        """
        Adds a command object to the manager.

        Keyword arguments:
        command_name - Name to associate with the command.
        command_object - WorkNodeExecutable object that will execute the
                         command.

        Return value:
        WorkNodeExecutable object.

        """
        self.__commands[command_name] = command_object
        return self.__commands[command_name]

    def get_command_object(self, command_name):
        """
        Get the requested command object.

        Keyword arguments:
        command_name - Name associated with the command.

        Return value:
        WorkNodeExecutable object.

        """
        if command_name not in self.__commands:
            raise NameError(
                "Command object for {0} doesn't exist".format(command_name)
            )
        return self.__commands[command_name]

    def _get_parent(self):
        return self.__parent

    def _get_manager(self):
        return self._get_parent()

    def _get_work_node(self):
        return self._get_parent()._get_work_node()

    def _get_soundcard_control_factory(self):
        return self.__soundcard_control_factory

    def _set_soundcard_control_factory(self, factory_object):
        self.__soundcard_control_factory = factory_object

    def get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def discover_controls(self):
        """
        Discover all of the controls present on the soundcard.

        """
        self.get_property_manager().refresh_properties()
        control_ids = self.get_property_manager().get_property_value(
            property_name = 'id',
        )
        self.__clear_control_list()
        factory = self._get_soundcard_control_factory()
        for num_id in control_ids:
            control = factory.get_soundcard_control(
                parent = self,
                num_id = num_id,
            )
            self.__add_control(control_object = control)

    def __add_control(self, control_object):
        self.__controls[int(control_object.get_id())] = control_object

    def __clear_control_list(self):
        for control in list(self.__controls.values()):
            del control
        for key in list(self.__controls.keys()):
            del self.__controls[key]

    def get_index(self):
        """
        Get the index number of the soundcard.

        Return value:
        Index number.

        """
        return self.__index

    def get_name(self):
        """
        Get the friendly name of the soundcard.

        Return value:
        String representing the name.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'card_name',
        )[0]

    def get_vendor_id(self):
        """
        Get the vendor ID of the sound card.

        Return value:
        Vendor ID of the sound card.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'vendor_id',
        )

    def get_device_id(self):
        """
        Get the device ID of the sound card.

        Return value:
        Device ID of the sound card.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'device_id',
        )

    def get_subsystem_vendor_id(self):
        """
        Get the subsystem vendor ID of the sound card.

        Return value:
        Subsystem vendor ID of the sound card.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'subsystem_vendor_id',
        )

    def get_subsystem_device_id(self):
        """
        Get the subsystem device ID of the sound card.

        Return value:
        Subsystem device ID of the sound card.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'subsystem_device_id',
        )

    def get_type(self):
        """
        Get the type of the sound card.

        Return value:
        String representation of the type of the sound card.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'card_type',
        )[0]

    def get_mixer_name(self):
        """
        Get the name of the sound card in the mixer.

        Return value:
        String representation of the name of the sound card in the mixer.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'mixer_name',
        )[0]

    def get_control(self, num_id):
        """
        Get the specified soundcard control object.

        Keyword arguments:
        num_id - ID number of the soundcard control to return.

        Return value:
        SoundcardControl object.

        """
        num_id = int(num_id)
        if num_id not in self.__controls:
            self.discover_controls()
        return self.__controls[num_id]

    def get_controls(self):
        """
        Get a list of all soundcard control objects.

        Return value:
        List of SoundcardControl objects.

        """
        if list(self.__controls.values()) == []:
            self.discover_controls()
        return list(self.__controls.values())

    def get_control_by_name(self, name):
        """
        Get the specified soundcard control object by its name.

        Keyword arguments:
        name - Name of the soundcard control to return.

        Return value:
        SoundcardControl

        """
        controls = self.get_controls()
        for control in controls:
            if control.get_name() == name:
                return control

    def __del__(self):
        self.__parent = None
        self.__index = None
        self.__clear_control_list()
        del self.__property_manager
        super(Soundcard, self).__del__()

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent}, index = {index})'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
            index = self.get_index(),
        )

class SoundcardControlFactory(framework.Framework):
    """
    Abstract: Factory class for generating SoundcardControl objects specific to
    the value types of the soundcard control.

    """
    def get_soundcard_control(self, parent, num_id):
        """
        Abstract: Method for getting a specific soundcard control.

        """
        raise NotImplementedError

class SoundcardControl(framework.Framework):
    """
    Class representing different types of soundcard controls.

    """
    def __init__(self, parent, num_id):
        super(SoundcardControl, self).__init__()
        self.__parent = parent
        self.__property_manager = worknode.property_manager.PropertyManager(
            work_node = self._get_work_node(),
        )
        self.__id = int(num_id)
        self.__commands = {}
        self.__initialize_property_manager()

    def __initialize_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'name')
        property_manager.initialize_property(property_name = 'interface')
        property_manager.initialize_property(property_name = 'type')
        property_manager.initialize_property(property_name = 'access')
        property_manager.initialize_property(property_name = 'number_of_values')
        property_manager.initialize_property(property_name = 'values')

    def add_command(self, command_name, command_object):
        """
        Adds a command object to the manager.

        Keyword arguments:
        command_name - Name to associate with the command.
        command_object - WorkNodeExecutable object that will execute the
                         command.

        Return value:
        WorkNodeExecutable object.

        """
        self.__commands[command_name] = command_object
        return self.__commands[command_name]

    def get_command_object(self, command_name):
        """
        Get the requested command object.

        Keyword arguments:
        command_name - Name associated with the command.

        Return value:
        WorkNodeExecutable object.

        """
        if command_name not in self.__commands:
            raise NameError(
                "Command object for {0} doesn't exist".format(command_name)
            )
        return self.__commands[command_name]

    def _get_parent(self):
        return self.__parent

    def _get_work_node(self):
        return self._get_parent()._get_work_node()

    def _get_soundcard(self):
        return self._get_parent()

    def get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def get_id(self):
        """
        Get the ID number of the soundcard control.

        Return value:
        ID number.

        """
        return self.__id

    def get_name(self):
        """
        Get the name of the soundcard control.

        Return value:
        Name of the control.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'name',
        )[0]

    def get_interface(self):
        """
        Get the interface of the soundcard control.

        Return value:
        Interface of the soundcard control.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'interface',
        )[0]

    def get_type(self):
        """
        Get the data type of the soundcard control value(s).

        Return value:
        String describing the data type of the soundcard control value(s).

        """
        return self.get_property_manager().get_property_value(
            property_name = 'type',
        )[0]

    def get_access(self):
        """
        Get the access control values of the soundcard control.

        Return value:
        Access control values string.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'access',
        )[0]

    def get_number_of_values(self):
        """
        Get the number of values of the soundcard control.

        Return value:
        Number of values of the soundcard control.

        """
        return int(
            self.get_property_manager().get_property_value(
                property_name = 'number_of_values',
            )[0]
        )

    def get_values(self):
        """
        Get the value(s) of the soundcard control.

        Return value:
        Value(s) of the soundcard control.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'values',
        )[0]

    def is_read_only(self):
        """
        Abstract: Check if the soundcard control is read only.

        Return value:
        True if the soundcard control is read only, False otherwise.

        """
        raise NotImplementedError

    def set_raw_value(self, value, preferred_command = None):
        """
        Abstract: Set the raw value of the soundcard control.

        Keyword arguments:
        value - Value to set the control to.
        preferred_command - Command to use when performing the action.

        """
        raise NotImplementedError

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent}, num_id = {num_id})'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
            num_id = self.get_id(),
        )
