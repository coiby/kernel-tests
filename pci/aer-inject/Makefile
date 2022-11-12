# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/pci/aer-inject
#   Description: PCI-E Advanced Error Reporting (AER) software injection testing
#   Author: William R. Gomeringer <wgomerin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc. All rights reserved.
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

export TEST=/kernel/pci/aer-inject
export TESTVERSION=1.0

# Create target for aer-inject tarball
# URL: http://www.kernel.org/pub/linux/utils/pci/aer-inject/aer-inject-0.1.tar.bz2
export AERINJECTVERSION=0.1
TARGET=aer-inject-$(AERINJECTVERSION)

FILES=$(METADATA) $(TARGET).tar.bz2 runtest.sh Makefile PURPOSE

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build:
	chmod a+x runtest.sh
	# In RHEL6.1, aer-inject is included in the ras-utils package, so no need to compile.
	#@echo "--------------- Start aer-inject tool build ---------------"
	#tar -xvf $(TARGET).tar.bz2
	#make -C $(TARGET)
	#cp $(TARGET)/aer-inject /usr/local/sbin/

clean:
	rm -rf *~ $(TARGET) /usr/local/sbin/aer-inject


include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           William R. Gomeringer <wgomerin@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     PCI-E Advanced Error Reporting (AER) software injection testing" >> $(METADATA)
	@echo "Type:            Regression" >> $(METADATA)
	@echo "TestTime:        30m" >> $(METADATA)
	#@echo "Requires:        root" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)

	rhts-lint $(METADATA)
