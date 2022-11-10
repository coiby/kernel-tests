# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/wireless_tests/functional/connection/wpa_supplicant/wireless_connection_to_WPA1_TLS_AP
#   Description: Test code for wireless connection to a WPA1 TLS AP
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

export TEST=/kernel/wireless_tests/functional/connection/wpa_supplicant/wireless_connection_to_WPA1_TLS_AP
export TESTVERSION=1.0
export PATH:=$(PATH):/mnt/tests/kernel/test-framework/

BUILT_FILES=

FILES=$(METADATA) __init__.py PURPOSE runtest.sh test.py

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x runtest.sh test.py

clean:
	rm -f *~ $(BUILT_FILES)


include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Ken Benoit <kbenoit@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     Establish a wireless connection to a WPA1 TLS AP." >> $(METADATA)
	@echo "TestTime:        5m" >> $(METADATA)
	@echo "RunFor:          kernel" >> $(METADATA)
	@echo "Requires:        dhclient wget wpa_supplicant dbus-tools" >> $(METADATA)
	@echo "RhtsRequires:	kernel-kernel-test-framework kernel-kernel-wireless_tests kernel-kernel-wireless_tests-functional kernel-kernel-wireless_tests-functional-connection kernel-kernel-wireless_tests-functional-connection-wpa_supplicant" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Type:            WiFi-Regression" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)

	rhts-lint $(METADATA)

