# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/power-management/turbostat/sanity
#   Description: Confirm turbostat is supported
#   Author: Evan McNabb <emcnabb@redhat.com>
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

export TEST=/kernel/power-management/turbostat/sanity
export TESTVERSION=1.0

BUILT_FILES=

FILES=$(METADATA) runtest.sh Makefile PURPOSE

.PHONY: all install download clean

run: $(FILES) build
        ./runtest.sh

build: $(BUILT_FILES)
        test -x runtest.sh || chmod a+x runtest.sh

clean:
        rm -f *~ $(BUILT_FILES)


include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
        @echo "Owner:           Evan McNabb <emcnabb@redhat.com>" > $(METADATA)
        @echo "Name:            $(TEST)" >> $(METADATA)
        @echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
        @echo "Path:            $(TEST_DIR)" >> $(METADATA)
        @echo "Description:     Confirm turbostat is supported" >> $(METADATA)
        @echo "Type:            Sanity" >> $(METADATA)
        @echo "TestTime:        5m" >> $(METADATA)
        @echo "RunFor:          kernel" >> $(METADATA)
        @echo "Requires:        kernel" >> $(METADATA)
        @echo "Requires:        kernel-tools" >> $(METADATA)
        @echo "Requires:        cpupowerutils" >> $(METADATA)
        @echo "Priority:        Normal" >> $(METADATA)
        @echo "License:         GPLv2" >> $(METADATA)
        @echo "Confidential:    no" >> $(METADATA)
        @echo "Architectures:   x86_64 i386" >> $(METADATA)
        @echo "Destructive:     no" >> $(METADATA)

        rhts-lint $(METADATA)
