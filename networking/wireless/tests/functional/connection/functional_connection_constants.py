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
Constant values used for functional connection tests.

"""

__author__ = 'Ken Benoit'

# Address to ping for connection test
PING_ADDRESS = 'www.redhat.com'

# URLs
CA_CERT_URL = 'http://tools.lab.eng.brq2.redhat.com:8080/ca.pem'
CLIENT_CERT_URL = 'http://tools.lab.eng.brq2.redhat.com:8080/client.pem'
PRIVATE_KEY_URL = 'http://tools.lab.eng.brq2.redhat.com:8080/client.pem'

# File names
LOCAL_CERT_DIR = '/etc/pki/wireless/'
CA_CERT_LOCAL_FILE = 'certificate_authority'
CLIENT_CERT_LOCAL_FILE = 'client'
PRIVATE_KEY_LOCAL_FILE = 'private_key'

# Backup file names
WPA_SUPPLICANT_CONF_BACKUP_FILE = '/etc/wpa_supplicant/wpa_supplicant.conf.backup'
WPA_SUPPLICANT_SYSCONFIG_BACKUP_FILE = '/etc/sysconfig/wpa_supplicant.backup'
