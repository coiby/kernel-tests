#!/bin/sh

# Source the common test script helpers
. ../../general/include/include.h
clean_env
setup_env
TEST="/kernel/memory/mmap1"

# ---------- Start Test -------------
# Setup some variables
if [ -e /etc/redhat-release ] ; then
    installeddistro=$(cat /etc/redhat-release)
else
    installeddistro=unknown
fi

kernbase=$(rpm -q --queryformat '%{name}-%{version}-%{release}.%{arch}\n' -qf /boot/config-$(uname -r))

echo "***** Starting the runtest.sh script *****" | tee -a $OUTPUTFILE
echo "***** Current Running Kernel Package = "$kernbase" *****" | tee -a $OUTPUTFILE
echo "***** Current Running Distro = "$installeddistro" *****" | tee -a $OUTPUTFILE

cc -O -g -Wall -I /usr/include/ -c -o mmaptst.o mmaptst.c
cc -o mmaptst mmaptst.o
./mmaptst 2>&1 >> $OUTPUTFILE

echo "***** End of runtest.sh *****" | tee -a $OUTPUTFILE

# ---------- Examine results -------------

# Default result to FAIL
export result="FAIL"

# Then post-process the results to find the regressions
export pass=`cat $OUTPUTFILE | grep "Pass" | wc -l`

if test ! -s "$OUTPUTFILE" ; then
    export result="FAIL"
else    
    if [ "$pass" -gt "0" ] ; then
        export result="PASS"
    else
        export result="FAIL"
    fi
fi
# Then file the results in the database
rstrnt-report-result $TEST $result 0
