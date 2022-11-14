# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/mce-test/mcelog
#   Description: mcelog functionality test
#   Author: Evan McNabb <emcnabb@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
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

export TEST=/kernel/mce-test/mcelog
export TESTVERSION=1.0

FILES=$(METADATA) runtest.sh Makefile PURPOSE 

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build: 
	chmod a+x runtest.sh

clean:
	rm -rf *~ mcelog* mce-inject* /usr/sbin/mce-inject /usr/bin/page-types

include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Evan McNabb <emcnabb@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     mcelog functionality test" >> $(METADATA)
	@echo "Architectures:   x86_64" >> $(METADATA)
	@echo "Releases:        RHEL6" >> $(METADATA)
	@echo "TestTime:        30m" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	@echo "Requires:        cronie crontabs psmisc git gcc flex bison rpm-build wget" >> $(METADATA)
	@echo "RhtsRequires:    mcelog kernel-kernel-mce-test-include" >>$(METADATA)

	rhts-lint $(METADATA)
