#!/usr/bin/env python
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   trex_sport.py of /kernel/networking/fd_nic_partition/bond
#   Author: Hekai Wang <hewang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


import argparse
import getopt
import json
import sys
import time

sys.path.append('/opt/trex/current/automation/trex_control_plane/stl/examples')
sys.path.append('./v2.48/automation/automation/trex_control_plane/interactive/trex/examples')
sys.path.append('./v2.48/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./v2.48/automation/trex_control_plane/stf/trex_stf_lib/')
sys.path.append('./v2.49/automation/automation/trex_control_plane/interactive/trex/examples')
sys.path.append('./v2.49/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./v2.49/automation/trex_control_plane/stf/trex_stf_lib/')
sys.path.append('./current/automation/trex_control_plane/interactive/trex/examples')
sys.path.append('./current/automation/trex_control_plane/interactive/trex/examples/stl')
sys.path.append('./current/automation/trex_control_plane/stf/trex_stf_lib/')

import stl_path
from trex_stl_lib.api import (STLClient, STLFlowStats, STLPktBuilder,
                              STLStream, STLTXCont)

from scapy.layers.inet import ICMP, IP, TCP, UDP
from scapy.layers.l2 import Dot1Q, Ether
import socket

class TrexTest(object):
    def __init__(self, trex_host):
        self.trex_host = socket.gethostbyname(trex_host)
        pass

    def start_trex_server(self):
        import trex_client
        import trex_status
        trex = trex_client.CTRexClient(self.trex_host, trex_args="--no-ofed-check")
        trex.force_kill(confirm=False)

        time.sleep(3)
        print("Before Running, TRex status is: {}".format(trex.is_running()))
        print("Before Running, TRex status is: {}".format(
            trex.get_running_status()))

        self.trex_config = trex.get_trex_config()
        import yaml
        t_config_obj = yaml.load(self.trex_config)
        """
        - version: 2
        interfaces: ['05:00.0', '05:00.1']
        #interfaces: ['enp5s0f0', 'enp5s0f1']
        port_info:
            - dest_mac: 90:e2:ba:29:bf:15 # MAC OF LOOPBACK TO IT'S DUAL INTERFACE
              src_mac:  90:e2:ba:29:bf:14
            - dest_mac: 90:e2:ba:29:bf:14 # MAC OF LOOPBACK TO IT'S DUAL INTERFACE
              src_mac:  90:e2:ba:29:bf:15

        platform:
            master_thread_id: 0
            latency_thread_id: 1
            dual_if:
                - socket: 0
                threads: [2,4,6,8,10,12,14]
        """
        core_num = len(t_config_obj[0]['platform']['dual_if'][0]['threads'])
        # t_config_obj["platform"]["dual_if"]["threads"].len()
        trex.trex_args = "-c {}".format(core_num)
        trex.start_stateless()
        # trex.get_trex_config()
        print("After Starting, TRex status is: {},{}".format(
            trex.is_running(), trex.get_running_status()))
        print("Is TRex running? {},{}".format(
            trex.is_running(), trex.get_running_status()))
        self.trex = trex
        self.trex_config = trex.get_trex_config()
        return self.trex

    def start_all_test(self):
        try:
            self.start_trex_server()
            import time
            time.sleep(10)
        except Exception as e:
            print(e)

