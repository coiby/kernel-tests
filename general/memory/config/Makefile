# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of regression
#   Description:
#   Author: Wang Shu <shuwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
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

TENV=_env
ifeq ($(PKG_TOP_DIR),)
	export PKG_TOP_DIR := $(shell p=$$PWD; while :; do \
		[ -e $$p/env.mk -o -z "$$p" ] && { echo $$p; break; }; p=$${p%/*}; done)
	export _TOP_DIR := $(shell p=$$PWD; while :; do \
		[ -d $$p/.git -o -z "$$p" ] && { echo $$p; break; }; p=$${p%/*}; done)
	-include $(PKG_TOP_DIR)/env.mk
endif
include $(TENV)
ifeq ($(_TOP_DIR),)
	_TOP_DIR=/mnt/tests/$(TOPLEVEL_NAMESPACE)
endif

export TESTVERSION=1.1

BUILT_FILES=

FILES=$(TENV) $(METADATA) runtest.sh Makefile PURPOSE testcase lib

.PHONY: all install download clean

run: $(FILES)  build
	./runtest.sh

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh

reset:
	find -name *.sh.done | sed 's/.sh.done/.sh/g' | xargs -I "{}" mv -v {}.done {}

dbg: testcase
	-mkdir debug
	-touch debug/DEBUG

cleanall: clean
	rm -fr *~ $(BUILT_FILES) tmp.* RS_*\.[0-9]* debug *.log

