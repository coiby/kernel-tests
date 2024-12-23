#!/bin/bash -x

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
# Author: Li Wang <liwang@redhat.com>

export OUTPUTFILE=/mnt/testarea/get_sem_otime.log
if [ -e $OUTPUTFILE ]; then
	rm -f $OUTPUTFILE
fi
TEST=/kernel/general/scheduler/bz1168588-sempo-semtimedop-does-not-update-sem_otime
RESULT=PASS
SEMID=
GET_SEM_OTIMES=

if [ -f call_semop.cc ] && [ -f get_sem_otime.cc ]; then
        g++ -o call_semop call_semop.cc
        g++ -o get_sem_otime get_sem_otime.cc
else
        echo "LOGINFO: Sorry, $(pwd)call_semop.cc or $(pwd)get_sem_otime.cc does not exist."
        exit 1;
fi

if [ -f call_semop ] && [ -f get_sem_otime ]; then
        ./call_semop 8913242 >> $OUTPUTFILE &

        sleep 3;
        SEMID=`grep semid $OUTPUTFILE| cut -d ' ' -f 5`
        echo "SEMID = $SEMID"
        sleep 3;
        SEMID=`grep semid $OUTPUTFILE| cut -d ' ' -f 5`
        echo "SEMID = $SEMID"
        if [ "$SEMID" = "" ]; then
                echo "LOGINFO: the SEMID does not exist..."
                exit 1;
        fi

        # the get_sem_otime should be run many times then check the value
        sleep 3;
        GET_SEM_OTIMES=`./get_sem_otime $SEMID`
        echo "GET_SEM_OTIMES= $GET_SEM_OTIMES"

        sleep 3;
        GET_SEM_OTIMES=`./get_sem_otime $SEMID`
        echo "GET_SEM_OTIMES= $GET_SEM_OTIMES"

        sleep 3;
        GET_SEM_OTIMES=`./get_sem_otime $SEMID`
        echo "GET_SEM_OTIMES= $GET_SEM_OTIMES"

        sleep 3;
        GET_SEM_OTIMES=`./get_sem_otime $SEMID`
        echo "GET_SEM_OTIMES= $GET_SEM_OTIMES"
        if [ "$GET_SEM_OTIMES" -gt 11 ]; then
                RESULT=FAIL
        fi
        echo $RESULT
else
        exit 1;
fi

# cleanup
killall call_semop
set -x
ipcrm -s "$SEMID"
set +x

rstrnt-report-result $TEST $RESULT
rstrnt-report-log -l ${OUTPUTFILE}
