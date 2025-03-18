# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of regression
#	Description: copy from vmm reg suit. for process testing.
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
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

.PHONY: run module reset dbg clean

run: build
	./runtest.sh

build:
	test -x runtest.sh || chmod a+x runtest.sh

module:
	yum -y install libelf-dev || yum -y install libelf-devel || yum -y install elfutils-libelf-devel
	-(. ./brew_kpkg_install.sh;\
	brew_kpkg_install pkg_kdevel pkg_kdebuginfo)
	sh -c "unset ARCH; cd testcase/module/spurious_waker; make"

reset: testDone
	-mv testDone/*.sh testcase/
	rmdir testDone

dbg: testcase
	-mkdir debug
	-touch debug/DEBUG

clean:
	rm -fr *~ $(BUILT_FILES) tmp.* RS_*\.[0-9]* debug *.log
	sh -c "unset ARCH; cd testcase/module/spurious_waker; make clean; cd -; cd testcase/module; make clean"
