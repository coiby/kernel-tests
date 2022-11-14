#!/usr/bin/python

import os
import sys
import interfaces
import wifi_test_harness

def test(c):
    c.driver = 'nl80211'
    c.eapol_version = '1'
    c.ap_scan = '1'
    c.fast_reauth = '1'
    c.ssid = 'qe-wpa1-enterprise'
    c.key_mgmt = 'WPA-EAP'
    c.proto = 'WPA'
    c.eap = 'TTLS'
    c.pairwise = 'TKIP'
    c.group = 'TKIP'
    c.phase2 = 'autheap=MSCHAPV2'
    c.identity = 'Bill Smith'
    c.password = 'testing123'
    c.ca_cert = os.path.realpath('eaptest_ca_cert.pem')

sys.exit(wifi_test_harness.main(test))
