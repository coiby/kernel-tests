# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/wireless_tests/functional/connection/nmcli
#   Description: Base wireless functional connection nmcli test directory
#   Author: Ken Benoit <kbenoit@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc. All rights reserved.
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

export TEST=/kernel/wireless_tests/functional/connection/nmcli
export TESTVERSION=1.0

BUILT_FILES=

FILES=$(METADATA) connection_base.py enterprise_connection_base.py __init__.py

.PHONY: all install download clean

clean:
	rm -f *~ $(BUILT_FILES) test.log


include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Ken Benoit <kbenoit@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     Base test for all nmcli functional connection tests." >> $(METADATA)
	@echo "TestTime:        1m" >> $(METADATA)
	@echo "RunFor:          kernel" >> $(METADATA)
	@echo "Requires:        iwl3945-firmware iwl6050-firmware iwl4965-firmware iwl5150-firmware iwl5000-firmware iwl6000-firmware iwl6000g2b-firmware iwl100-firmware iwl1000-firmware iwl6000g2a-firmware iwl105-firmware iwl135-firmware iwl2000-firmware iwl2030-firmware ar9170-firmware zd1211-firmware rt73usb-firmware rt61pci-firmware kernel wireless-tools wpa_supplicant dhclient NetworkManager rfkill net-tools iw pyOpenSSL" >> $(METADATA)
	@echo "RhtsRequires:	kernel-kernel-test-framework kernel-kernel-wireless_tests kernel-kernel-wireless_tests-functional kernel-kernel-wireless_tests-functional-connection" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)

	rhts-lint $(METADATA)
