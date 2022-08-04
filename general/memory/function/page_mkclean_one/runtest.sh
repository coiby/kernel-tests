#!/bin/sh

# Source the test script helpers
. /usr/bin/rhts-environment.sh

# ---------- Start Test -------------
testver=$(rpm -qf $0)
kernbase=$(rpm -q --queryformat '%{name}-%{version}-%{release}.%{arch}\n' -qf /boot/config-$(uname -r))

if [ -e /etc/redhat-release ] ; then
    installeddistro=$(cat /etc/redhat-release)
else
    installeddistro=unknown
fi

echo "***** Starting the runtest.sh script *****" | tee -a $OUTPUTFILE
echo "***** Current Test Package Version = $testver *****" | tee -a $OUTPUTFILE
echo "***** Current Running Kernel Package = $kernbase *****" | tee -a $OUTPUTFILE
echo "***** Current Running Distro = $installeddistro *****" | tee -a $OUTPUTFILE

result=PASS

echo "Running page_mkclean_one-check..." | tee -a $OUTPUTFILE
./page_mkclean_one-check | tee -a $OUTPUTFILE
# Fail if we get "Chunk.*corrupted" in the output
errors=$(grep -c "Chunk.*corrupted" $OUTPUTFILE)
if [ $errors -ge 1 ]; then
    result=FAIL
fi

echo "***** End of runtest.sh script *****" | tee -a $OUTPUTFILE

# --- then report the results in the database ---
report_result $TEST $result $errors
