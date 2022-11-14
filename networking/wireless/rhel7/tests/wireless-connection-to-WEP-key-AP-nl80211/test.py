#!/usr/bin/python

import sys
import interfaces
import wifi_test_harness

def test(c):
    c.driver = 'nl80211'
    c.eapol_version = '1'
    c.ap_scan = '1'
    c.fast_reauth = '1'
    c.ssid = 'qe-wep'
    c.key_mgmt = 'NONE'
    c.wep_tx_keyidx='0'
    c.wep_key0='74657374696E67313233343536'

sys.exit(wifi_test_harness.main(test))
