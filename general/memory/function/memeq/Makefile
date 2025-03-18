# Copyright (c) 2015 Red Hat, Inc. All rights reserved. This copyrighted
# material is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General Public
# License v.2.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
# 
# Author: Jiri Vohanka <jvohanka@redhat.com>
# Modify: Li Wang <liwang@redhat.com>

TOPLEVEL_NAMESPACE=kernel
PACKAGE_NAME=general/memory/function
RELATIVE_PATH=memeq

export TESTVERSION=2.0
export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)
 
# All files you want bundled into your rpm
FILES=	$(METADATA) \
    runtest.sh \
    Makefile \
    PURPOSE

.PHONY: clean run

clean:
	rm -f *~ $(METADATA)

run:
	@echo "No Build required"
	chmod +x ./runtest.sh
	./runtest.sh

