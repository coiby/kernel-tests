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
# Author: Artem Savkov <asavkov@redhat.com>

TOPLEVEL_NAMESPACE=kernel
PACKAGE_NAME=kpatch/integration-upstream

export TESTVERSION=1.0
export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)

BUILT_FILES=
FILES=$(METADATA) runtest.sh Makefile

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x runtest.sh

clean:
	rm -f *~ $(BUILT_FILES)

include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Artem Savkov <asavkov@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Description:     kpatch integration testing (upstream kernel)" $(METADATA)
	@echo "TestTime:        24h" >> $(METADATA)
	@echo "RunFor:          $(TOPLEVEL_NAMESPACE)" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPL" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	@echo "Requires:        $(PACKAGE_NAME) make mailx sendmail postfix git curl clang gcc grubby" >> $(METADATA)
