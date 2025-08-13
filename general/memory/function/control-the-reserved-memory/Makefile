#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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
#   Author: Li Wang <liwang@redhat.com>

# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=

# The name of the package under test:
PACKAGE_NAME=kernel

# The path of the test below the package:
RELATIVE_PATH=general/memory/function/control-the-reserved-memory

# Version of the Test. Used with make tag.
export TESTVERSION=1.0

# The combined namespace of the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

.PHONY: all install download clean

# executables to be built should be added here, they will be generated on the system under test.
BUILT_FILES=

# data files, .c files, scripts anything needed to either compile the test and/or run it.
FILES=$(METADATA) Makefile PURPOSE check-admin_reserve_kbytes.sh check-user_reserve_kbytes.sh

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh
	test -x check-admin_reserve_kbytes.sh || chmod a+x check-admin_reserve_kbytes.sh

clean:
	rm -f *~ $(BUILT_FILES)

