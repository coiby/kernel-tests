#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/vm/page_alloc
#   Description: VMM: physical page alloc
#   Author: Caspar Zhang <czhang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
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

# Include rhts environment
if [ -f /usr/bin/rhts-environment.sh ]; then
    . /usr/bin/rhts-environment.sh
fi
if [ -f ../../automotive/include/rhivos.sh ]; then
    . ../../automotive/include/rhivos.sh
    setup_env
fi

TESTAREA=/mnt/testarea
info1=$TESTAREA/info1
info2=$TESTAREA/info2
plotfile=$TESTAREA/plotfile

ARCH=$(arch)
if [ ${ARCH} != "ppc64" ] && [ ${ARCH} != "ppc64le" ] && [ ${ARCH} != "s390x" ]; then
    TEST="contiguous"
    RESULT=PASS
    echo "=== contiguous page alloc ===" | tee -a $OUTPUTFILE
    kdumpctl status || make -C ../../kdump/setup-bare-metal/ run
    # Ensure test is run when using tmt
    if [ -z ${TMT_PLAN_DATA} ]; then
        if [ ! "$RSTRNT_JOBID" ]; then
            if [ ${RSTRNT_REBOOTCOUNT} -eq 0 ]; then
                exit 0
            fi
        fi
    fi
    echo " - check cmdline:" | tee -a $OUTPUTFILE
    grep 'crashkernel' /proc/cmdline | tee -a $OUTPUTFILE
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo " - kdump is not running!" | tee -a $OUTPUTFILE
        RESULT=FAIL
    fi
    echo " - check 'Crash kernel' segment" | tee -a $OUTPUTFILE
    grep 'Crash kernel' /proc/iomem | tee -a $OUTPUTFILE
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo " - No 'Crash kernel' segment found!" | tee -a $OUTPUTFILE
        RESULT=FAIL
    fi
    rhts_submit_log -l /proc/iomem
    rhts-report-result $TEST $RESULT $OUTPUTFILE
    rm -f $OUTPUTFILE
    touch $OUTPUTFILE
fi # ppc64 & s390x doesn't execute contiguous test

TEST="non-contiguous"
RESULT=PASS
echo "=== non-contiguous page alloc ===" | tee -a $OUTPUTFILE
# RHEL5 doesn't have /proc/vmallocinfo?
if [ -e /proc/vmallocinfo ]; then
    echo " - show /proc/vmallocinfo" | tee -a $OUTPUTFILE
    cat /proc/vmallocinfo | tee -a $info1 | tee -a $OUTPUTFILE
fi
# execute some iptables rules to invoke vmalloc
echo " - call vmalloc by apply iptables rules" | tee -a $OUTPUTFILE
rm -f $plotfile
timeout=$((`date +%s`+3600))
/sbin/iptables -N chain_1 2>&1 | tee -a $OUTPUTFILE
for port in `seq 10000 19999`; do
    if [ $(($port%1000)) -eq 0 ]; then
        echo " - [`date`] port = $port" | tee -a $OUTPUTFILE
    fi
    /sbin/iptables -I chain_1 -s 127.0.0.1 -p udp --sport $port -j ACCEPT 2>&1
    if [ $? -ne 0 ] || [ `date +%s` -gt $timeout ]; then
        break;
    fi
    grep "VmallocUsed" /proc/meminfo | awk '{print $2}' >> $plotfile
done
if [ -e /proc/vmallocinfo ]; then
    echo " - show /proc/vmallocinfo again" | tee -a $OUTPUTFILE
    cat /proc/vmallocinfo | tee -a $info2 | tee -a $OUTPUTFILE
    echo " - show diff between two vmallocinfo files" | tee -a $OUTPUTFILE
    diff -Naur $info1 $info2 | tee -a $OUTPUTFILE
fi
echo " - draw picture of VmallocUsed changes" | tee -a $OUTPUTFILE
gnuplot <<EOF
#set style data linespoints
set term jpeg
set output "$plotfile.jpg"
plot "$plotfile"
EOF
echo " - please see the attached image!" | tee -a $OUTPUTFILE

rhts_submit_log -l $plotfile.jpg
rhts-report-result $TEST $RESULT $OUTPUTFILE
