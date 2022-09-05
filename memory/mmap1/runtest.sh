#!/bin/sh

# Source the common test script helpers
. /usr/bin/rhts_environment.sh

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
report_result $TEST $result 0
