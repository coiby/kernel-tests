# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/audio_tests/functional/record_audio_from_connected_outputs
#   Description: Test to play audio over the loopback cable of all connected
#                outputs.
#   Author: Ken Benoit <kbenoit@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc. All rights reserved.
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

export TEST=/kernel/audio_tests/functional/record_audio_from_connected_outputs
export TESTVERSION=2.0

BUILT_FILES=

FILES=$(METADATA) compare_audio.sh __init__.py PURPOSE runtest.sh test.py

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x runtest.sh test.py compare_audio.sh

clean:
	rm -f *~ $(BUILT_FILES) test.log *.pyc


include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Ken Benoit <kbenoit@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     Test to play audio over the loopback cable of all connected outputs (Requires properly configured loopback cabling on the test system)" >> $(METADATA)
	@echo "TestTime:        20m" >> $(METADATA)
	@echo "RunFor:          kernel" >> $(METADATA)
	@echo "Requires:        python alsa-utils sox pciutils" >> $(METADATA)
	@echo "RhtsRequires:	kernel-kernel-test-framework kernel-kernel-audio_tests-functional kernel-kernel-audio-utils-average_frequency_compare" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)

	rhts-lint $(METADATA)
