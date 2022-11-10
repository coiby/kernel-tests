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
The worknode.linux.manager.wireless_interface_map module provides a class
(WirelessInterfaceMapFactory) that provides a method of getting the descriptive
name of a wireless interface according to the vendor.

"""

__author__ = 'Ken Benoit'

import re

import framework

class WirelessInterfaceMapFactory(framework.Framework):
    """
    WirelessInterfaceMapFactory accepts a vendor ID and a device ID (PCI/USB ID)
    to determine the descriptive name of a wireless interface according to the
    vendor.

    """
    def __init__(self):
        super(WirelessInterfaceMapFactory, self).__init__()
        self.__map = {
            0x000b: {
                0x7300: 'Netgear MA401 B',
            },
            0x050d: {
                0x7050: 'Belkin Components F5D7050 Wireless G Adapter v1000/v2000 [Intersil ISL3887]',
            },
            0x0586: {
                0x3409: 'ZyXEL Communications AG-225H 802.11bg',
            },
            0x07d1: {
                0x3c04: 'D-Link System WUA-1340',
                0x3c13: 'D-Link System DWA-130 802.11n Wireless N Adapter(rev.B) [Ralink RT2870]',
            },
            0x0803: {
                0x4310: 'Zoom Telephonics 4410a Wireless-G Adapter [Intersil ISL3887]',
            },
            0x083a: {
                0x4505: 'Accton Technology SMCWUSB-G 802.11bg',
            },
            0x0846: {
                0x6a00: 'NetGear WG111v2 54 Mbps Wireless [RealTek RTL8187L]',
                0x9010: 'NetGear WNDA3100v1 802.11abgn [Atheros AR9170+AR9104]',
                0x9030: 'NetGear WNA1100 Wireless-N 150 [Atheros AR9271]',
            },
            0x0a5c: {
                0xd11b: 'Broadcom Eminent EM4045 [Broadcom 4320 USB]',
            },
            0x0ace: {
                0x1211: 'ZyDAS ZD1211 802.11g',
                0x1215: 'ZyDAS ZD1211B 802.11g',
            },
            0x0bda: {
                0x8187: 'Realtek Semiconductor RTL8187 Wireless Adapter',
            },
            0x0cf3: {
                0x9170: 'Atheros Communications AR9170 802.11n',
            },
            0x104c: {
                0x8400: 'Texas Instruments ACX 100 22Mbps Wireless Interface',
                0x9066: 'Texas Instruments ACX 111 54Mbps Wireless Interface',
            },
            0x10ec: {
                0x8180: 'Realtek Semiconductor RTL8180L 802.11b MAC',
                0x8185: 'Realtek Semiconductor RTL-8185 IEEE 802.11a/b/g Wireless LAN Controller',
                0x8190: 'Realtek Semiconductor RTL8190 802.11n Wireless LAN',
            },
            0x11ab: {
                0x1faa: 'Marvell Technology Group 88w8335 [Libertas] 802.11b/g Wireless',
                0x2a02: 'Marvell Technology Group 88W8361 [TopDog] 802.11n Wireless',
            },
            0x1260: {
                0x3873: 'Intersil ISL3874 [Prism 2.5]/ISL3872 [Prism 3]',
                0x3886: 'Intersil ISL3886 [Prism Javelin/Prism Xbow]',
                0x3890: 'Intersil ISL3890 [Prism GT/Prism Duette]/ISL3886 [Prism Javelin/Prism Xbow]',
            },
            0x1385: {
                0x4251: 'Netgear WG111T',
            },
            0x13b1: {
                0x0020: 'Linksys WUSB54GC v1 802.11g Adapter [Ralink RT73]',
                0x0029: 'Linksys WUSB300N 802.11bgn Wireless Adapter [Marvell 88W8362+88W8060]',
            },
            0x148f: {
                0x2573: 'Ralink Technology RT2501/RT2573 Wireless Adapter',
            },
            0x14e4: {
                0x4315: 'Broadcom BCM4312 802.11b/g LP-PHY',
                0x4318: 'Broadcom BCM4318 [AirForce One 54g] 802.11g Wireless LAN Controller',
                0x4320: 'Broadcom BCM4306 802.11b/g Wireless LAN Controller',
                0x4328: 'Broadcom BCM4321 802.11a/b/g/n',
                0x4329: 'Broadcom BCM4321 802.11b/g/n',
                0x4727: 'Broadcom BCM4313 802.11bgn Wireless Network Adapter',
            },
            0x157e: {
                0x3007: 'TRENDnet TEW-444UB EU',
                0x300d: 'TRENDnet TEW-429UB C1 802.11bg',
            },
            0x167b: {
                0x2116: 'ZyDAS Technology ZD1212B Wireless Adapter',
            },
            0x168c: {
                0x0007: 'Qualcomm Atheros AR5210 Wireless Network Adapter [AR5000 802.11a]',
                0x0012: 'Qualcomm Atheros AR5211 Wireless Network Adapter [AR5001X 802.11ab]',
                0x0013: 'Qualcomm Atheros AR5212/AR5213 Wireless Network Adapter',
                0x001a: 'Qualcomm Atheros AR2413/AR2414 Wireless Network Adapter [AR5005G(S) 802.11bg]',
                0x001b: 'Qualcomm Atheros AR5413/AR5414 Wireless Network Adapter [AR5006X(S) 802.11abg]',
                0x0020: 'Qualcomm Atheros AR5513 802.11abg Wireless NIC',
                0x0023: 'Qualcomm Atheros AR5416 Wireless Network Adapter [AR5008 802.11(a)bgn]',
                0x0024: 'Qualcomm Atheros AR5418 Wireless Network Adapter [AR5008E 802.11(a)bgn] (PCI-Express)',
                0x0032: 'Qualcomm Atheros AR9485 Wireless Network Adapter',
            },
            0x1740: {
                0x9702: 'Senao EnGenius 802.11n Wireless USB Adapter',
            },
            0x1799: {
                0x701f: 'Belkin F5D7010 v7000 Wireless G Notebook Card [Realtek RTL8185]',
            },
            0x1814: {
                0x0101: 'Ralink Wireless PCI Adapter RT2400 / RT2460',
                0x0301: 'Ralink RT2561/RT61 802.11g PCI',
                0x0401: 'Ralink RT2600 802.11 MIMO',
            },
            0x2001: {
                0x3704: 'D-Link AirPlus G DWL-G122 Wireless Adapter(rev.A2) [Intersil ISL3887]',
            },
            0x6891: {
                0xa727: '3Com 3CRUSB10075 802.11bg [ZyDAS ZD1211]',
            },
            0x8086: {
                0x0083: 'Intel Centrino Wireless-N 1000 [Condor Peak]',
                0x008a: 'Intel Centrino Wireless-N 1030 [Rainbow Peak]',
                0x0885: 'Intel Centrino Wireless-N + WiMAX 6150',
                0x0887: 'Intel Centrino Wireless-N 2230',
                0x088e: 'Intel Centrino Advanced-N 6235',
                0x0890: 'Intel Centrino Wireless-N 2200',
                0x0896: 'Intel Centrino Wireless-N 130',
                0x08ae: 'Intel Centrino Wireless-N 100',
                0x08b1: 'Intel Dual Band Wireless-AC 7260 [Wilkins Peak 2]',
                0x08b3: 'Intel Dual Band Wireless-AC 3160 [Wilkins Peak 1]',
                0x095a: 'Intel Dual Band Wireless-AC 7265 [Stone Peak]',
                0x4220: 'Intel PRO/Wireless 2200BG [Calexico2] Network Connection',
                0x4229: 'Intel PRO/Wireless 4965 AG or AGN [Kedron] Network Connection',
                0x422c: 'Intel Centrino Advanced-N 6200',
                0x4232: 'Intel WiFi Link 5100',
                0x4236: 'Intel Ultimate N WiFi Link 5300',
                0x4238: 'Intel Centrino Ultimate-N 6300',
            },
        }

    def get_descriptive_name(self, vendor_id, device_id):
        """
        Given the vendor ID and the device ID get the descriptive name of the
        wireless interface.

        Keyword arguments:
        vendor_id - Vendor ID in hex or decimal.
        device_id - Device ID in hex or decimal.

        """
        if type(vendor_id) is str:
            if re.match('^0x', vendor_id):
                vendor_id = int(vendor_id, 16)
            else:
                vendor_id = int(vendor_id)
        else:
            return "Unable to determine descriptive name"
        if type(device_id) is str:
            if re.match('^0x', device_id):
                device_id = int(device_id, 16)
            else:
                device_id = int(device_id)
        else:
            return "Unable to determine descriptive name"

        descriptive_name = '{0:02x}:{1:02x}'.format(vendor_id, device_id)

        if vendor_id in self.__map:
            if device_id in self.__map[vendor_id]:
                descriptive_name = self.__map[vendor_id][device_id]

        return descriptive_name
