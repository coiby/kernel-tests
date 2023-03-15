#!/usr/bin/python

import sys
import interfaces
import wifi_test_harness

def test(c):
    c.driver = 'nl80211'
    c.eapol_version = '1'
    c.ap_scan = '1'
    c.fast_reauth = '1'
    c.ssid = 'qe-open'
    c.key_mgmt = 'NONE'

sys.exit(wifi_test_harness.main(test))
