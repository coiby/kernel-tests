#!/bin/sh

# Source the test script helpers
. ../../../../general/include/include.h
clean_env
setup_env
TEST="/kernel/general/memory/function/page_mkclean_one"
OUTPUTFILE=${OUTPUTFILE:-/mnt/testarea/outputfile.$(pwd | md5sum | awk '{print $1}' | cut -c 1-8)}

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
gcc -o page_mkclean_one-check page_mkclean_one-check.c
./page_mkclean_one-check | tee -a $OUTPUTFILE
# Fail if we get "Chunk.*corrupted" in the output
errors=$(grep -c "Chunk.*corrupted" $OUTPUTFILE)
if [ $errors -ge 1 ]; then
    result=FAIL
fi

echo "***** End of runtest.sh script *****" | tee -a $OUTPUTFILE

# --- then report the results in the database ---
rstrnt-report-result $TEST $result $errors
