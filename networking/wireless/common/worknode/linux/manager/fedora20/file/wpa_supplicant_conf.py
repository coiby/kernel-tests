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
The worknode.linux.manager.fedora20.file.wpa_supplicant module provides a class
(ConfigFileManager) that manages the config files present on the work node.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.file.wpa_supplicant_conf

class WpaSupplicantConf(worknode.linux.file.wpa_supplicant_conf.WpaSupplicantConf):
    """
    WpaSupplicantConf represents the wpa_supplicant.conf config file and the
    methods of reading and writing the file.

    """
    def __init__(self, work_node):
        super(WpaSupplicantConf, self).__init__(work_node = work_node)
        self._set_file_path(file_path = '/etc/wpa_supplicant/wpa_supplicant.conf')
        self._set_reader(reader = _reader)
        self._set_writer(writer = _writer)

    def set_ctrl_interface(self, property_value):
        self.__properties['ctrl_interface'] = str(property_value)

    def set_ctrl_interface_group(self, property_value):
        self.__properties['ctrl_interface_group'] = str(property_value)

    def set_eapol_version(self, property_value):
        self.__properties['eapol_version'] = str(property_value)

    def set_ap_scan(self, property_value):
        self.__properties['ap_scan'] = str(property_value)

    def set_fast_reauth(self, property_value):
        self.__properties['fast_reauth'] = str(property_value)

    def set_opensc_engine_path(self, property_value):
        self.__properties['opensc_engine_path'] = str(property_value)

    def set_pkcs11_engine_path(self, property_value):
        self.__properties['pkcs11_engine_path'] = str(property_value)

    def set_pkcs11_module_path(self, property_value):
        self.__properties['pkcs11_module_path'] = str(property_value)

    def set_load_dynamic_eap(self, property_value):
        self.__properties['load_dynamic_eap'] = str(property_value)

    def set_country(self, property_value):
        self.__properties['country'] = str(property_value)

    def set_dot11RSNAConfigPMKLifetime(self, property_value):
        self.__properties['dot11RSNAConfigPMKLifetime'] = str(property_value)

    def set_dot11RSNAConfigPMKReauthThreshold(self, property_value):
        self.__properties['dot11RSNAConfigPMKReauthThreshold'] = str(property_value)

    def set_dot11RSNAConfigSATimeout(self, property_value):
        self.__properties['dot11RSNAConfigSATimeout'] = str(property_value)

    def set_uuid(self, property_value):
        self.__properties['uuid'] = str(property_value)

    def set_device_name(self, property_value):
        self.__properties['device_name'] = str(property_value)

    def set_manufacturer(self, property_value):
        self.__properties['manufacturer'] = str(property_value)

    def set_model_name(self, property_value):
        self.__properties['model_name'] = str(property_value)

    def set_model_number(self, property_value):
        self.__properties['model_number'] = str(property_value)

    def set_serial_number(self, property_value):
        self.__properties['serial_number'] = str(property_value)

    def set_device_type(self, property_value):
        self.__properties['device_type'] = str(property_value)

    def set_os_version(self, property_value):
        self.__properties['os_version'] = str(property_value)

    def set_config_methods(self, property_value):
        self.__properties['config_methods'] = str(property_value)

    def set_wps_cred_processing(self, property_value):
        self.__properties['wps_cred_processing'] = str(property_value)

    def set_bss_max_count(self, property_value):
        self.__properties['bss_max_count'] = str(property_value)

    def create_network_block(self):
        if 'network' not in self.__properties:
            self.__properties['network'] = []
        self.__properties['network'].append({})
        index = len(self.__properties['network']) - 1
        return index

    def set_network_disabled(self, property_value, block = 0):
        self.__properties['network'][block]['disabled'] = str(property_value)

    def set_network_id_str(self, property_value, block = 0):
        self.__properties['network'][block]['id_str'] = str(property_value)

    def set_network_ssid(self, property_value, block = 0):
        self.__properties['network'][block]['ssid'] = str(property_value)

    def set_network_scan_ssid(self, property_value, block = 0):
        self.__properties['network'][block]['scan_ssid'] = str(property_value)

    def set_network_bssid(self, property_value, block = 0):
        self.__properties['network'][block]['bssid'] = str(property_value)

    def set_network_priority(self, property_value, block = 0):
        self.__properties['network'][block]['priority'] = str(property_value)

    def set_network_mode(self, property_value, block = 0):
        self.__properties['network'][block]['mode'] = str(property_value)

    def set_network_frequency(self, property_value, block = 0):
        self.__properties['network'][block]['frequency'] = str(property_value)

    def set_network_scan_freq(self, property_value, block = 0):
        self.__properties['network'][block]['scan_freq'] = str(property_value)

    def set_network_freq_list(self, property_value, block = 0):
        self.__properties['network'][block]['freq_list'] = str(property_value)

    def set_network_proto(self, property_value, block = 0):
        self.__properties['network'][block]['proto'] = str(property_value)

    def set_network_key_mgmt(self, property_value, block = 0):
        self.__properties['network'][block]['key_mgmt'] = str(property_value)

    def set_network_auth_alg(self, property_value, block = 0):
        self.__properties['network'][block]['auth_alg'] = str(property_value)

    def set_network_pairwise(self, property_value, block = 0):
        self.__properties['network'][block]['pairwise'] = str(property_value)

    def set_network_group(self, property_value, block = 0):
        self.__properties['network'][block]['group'] = str(property_value)

    def set_network_psk(self, property_value, block = 0):
        self.__properties['network'][block]['psk'] = str(property_value)

    def set_network_eapol_flags(self, property_value, block = 0):
        self.__properties['network'][block]['eapol_flags'] = str(property_value)

    def set_network_mixed_cell(self, property_value, block = 0):
        self.__properties['network'][block]['mixed_cell'] = str(property_value)

    def set_network_proactive_key_caching(self, property_value, block = 0):
        self.__properties['network'][block]['proactive_key_caching'] = str(property_value)

    def set_network_wep_key0(self, property_value, block = 0):
        self.__properties['network'][block]['wep_key0'] = str(property_value)

    def set_network_wep_key1(self, property_value, block = 0):
        self.__properties['network'][block]['wep_key1'] = str(property_value)

    def set_network_wep_key2(self, property_value, block = 0):
        self.__properties['network'][block]['wep_key2'] = str(property_value)

    def set_network_wep_key3(self, property_value, block = 0):
        self.__properties['network'][block]['wep_key3'] = str(property_value)

    def set_network_peerkey(self, property_value, block = 0):
        self.__properties['network'][block]['peerkey'] = str(property_value)

    def set_network_wpa_ptk_rekey(self, property_value, block = 0):
        self.__properties['network'][block]['wpa_ptk_rekey'] = str(property_value)

    def set_network_eap(self, property_value, block = 0):
        self.__properties['network'][block]['eap'] = str(property_value)

    def set_network_identity(self, property_value, block = 0):
        self.__properties['network'][block]['identity'] = str(property_value)

    def set_network_anonymous_identity(self, property_value, block = 0):
        self.__properties['network'][block]['anonymous_identity'] = str(property_value)

    def set_network_password(self, property_value, block = 0):
        self.__properties['network'][block]['password'] = str(property_value)

    def set_network_ca_cert(self, property_value, block = 0):
        self.__properties['network'][block]['ca_cert'] = str(property_value)

    def set_network_ca_path(self, property_value, block = 0):
        self.__properties['network'][block]['ca_path'] = str(property_value)

    def set_network_client_cert(self, property_value, block = 0):
        self.__properties['network'][block]['client_cert'] = str(property_value)

    def set_network_private_key(self, property_value, block = 0):
        self.__properties['network'][block]['private_key'] = str(property_value)

    def set_network_private_key_passwd(self, property_value, block = 0):
        self.__properties['network'][block]['private_key_passwd'] = str(property_value)

    def set_network_dh_file(self, property_value, block = 0):
        self.__properties['network'][block]['dh_file'] = str(property_value)

    def set_network_subject_match(self, property_value, block = 0):
        self.__properties['network'][block]['subject_match'] = str(property_value)

    def set_network_altsubject_match(self, property_value, block = 0):
        self.__properties['network'][block]['altsubject_match'] = str(property_value)

    def set_network_phase1(self, property_value, block = 0):
        self.__properties['network'][block]['phase1'] = str(property_value)

    def set_network_phase2(self, property_value, block = 0):
        self.__properties['network'][block]['phase2'] = str(property_value)

    def set_network_ca_cert2(self, property_value, block = 0):
        self.__properties['network'][block]['ca_cert2'] = str(property_value)

    def set_network_ca_path2(self, property_value, block = 0):
        self.__properties['network'][block]['ca_path2'] = str(property_value)

    def set_network_client_cert2(self, property_value, block = 0):
        self.__properties['network'][block]['client_cert2'] = str(property_value)

    def set_network_private_key2(self, property_value, block = 0):
        self.__properties['network'][block]['private_key2'] = str(property_value)

    def set_network_private_key2_passwd(self, property_value, block = 0):
        self.__properties['network'][block]['private_key2_passwd'] = str(property_value)

    def set_network_dh_file2(self, property_value, block = 0):
        self.__properties['network'][block]['dh_file2'] = str(property_value)

    def set_network_subject_match2(self, property_value, block = 0):
        self.__properties['network'][block]['subject_match2'] = str(property_value)

    def set_network_altsubject_match2(self, property_value, block = 0):
        self.__properties['network'][block]['altsubject_match2'] = str(property_value)

    def set_network_fragment_size(self, property_value, block = 0):
        self.__properties['network'][block]['fragment_size'] = str(property_value)

    def set_network_pac_file(self, property_value, block = 0):
        self.__properties['network'][block]['pac_file'] = str(property_value)

def _reader(file_contents):
    properties = {}
    property_dictionary_name = None
    for line in file_contents:
        if property_dictionary_name is None:
            if re.search('\w+=\{', line):
                match = re.search('(?P<property_name>\w+)=\{', line)
                property_name = match.group('property_name')
                if property_name in properties:
                    properties[property_name].append({})
                else:
                    properties[property_name] = [{}]
                property_dictionary_name = property_name
            else:
                match = re.search('(?P<property_name>\w+)=(?P<property_value>.+?)\n', line)
                property_name = match.group('property_name')
                property_value = match.group('property_value')
                properties[property_name] = property_value.strip()
        else:
            if re.search('\}', line):
                property_dictionary_name = None
            else:
                match = re.search('(?P<property_name>\w+)=(?P<property_value>.+?)\n', line)
                property_name = match.group('property_name')
                property_value = match.group('property_value')
                properties[property_dictionary_name][-1][property_name] = property_value
    return properties

def _writer(properties):
    lines = []
    for (property_key, property_value) in properties.items():
        if type(property_value) is list:
            for block in property_value:
                lines.append(property_key + '={\n')
                for (subsection_property_key, subsection_property_value) in block.items():
                    lines.append('    {key}={value}\n'.format(key = subsection_property_key, value = subsection_property_value))
                lines.append('}\n')
        else:
            lines.append('{key}={value}\n'.format(key = property_key, value = property_value))
    return lines
