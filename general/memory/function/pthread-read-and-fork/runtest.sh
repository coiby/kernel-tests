#!/bin/sh

# Source the common test script helpers
. /usr/bin/rhts_environment.sh

# Helper functions
function TestHeader ()
{
    echo "***** Starting hugetlb pthread read and fork test *****" | tee -a $OUTPUTFILE
    echo "***** Current Running Kernel Package = "$kernbase" *****" | tee -a $OUTPUTFILE
    echo "***** Current Running Distro = "$installeddistro" *****" | tee -a $OUTPUTFILE
    echo "*************************************" | tee -a $OUTPUTFILE
}

# ---------- Start Test -------------
# Setup some variables
if [ -e /etc/redhat-release ] ; then
    installeddistro=$(cat /etc/redhat-release)
else
    installeddistro=unknown
fi

kernbase=$(rpm -q --queryformat '%{name}-%{version}-%{release}.%{arch}\n' -qf /boot/config-$(uname -r))
nr_huge_old=$(cat /proc/sys/vm/nr_hugepages)

OUTPUTFILE=`mktemp /tmp/tmp.XXXXXX`
TestHeader

pagesize=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')
let hugepages=1048576/$pagesize
echo "Huge Page Size: $pagesize kB ($hugepages Huge Pages per GB)" | tee -a $OUTPUTFILE

echo "Compiling test binary" | tee -a $OUTPUTFILE
gcc -D_GNU_SOURCE -lpthread -o pthread-read-and-fork pthread-read-and-fork.c

echo "Setting up hugetlbfs" | tee -a $OUTPUTFILE
mkdir /huge
mount -t hugetlbfs hugetlbfs /huge
echo $hugepages > /proc/sys/vm/nr_hugepages

# we need two block devices to read from, just use /boot and /
dev1=$(df -h /boot | grep "^/dev" | awk '{print $1}')
dev2=$(df -h / | grep "^/dev" | awk '{print $1}')

# Execute the reproducer
echo "Starting the actual test run on $dev1 and $dev2..." | tee -a $OUTPUTFILE
./pthread-read-and-fork $dev1 &
./pthread-read-and-fork $dev2 &

# Let stuff run for half an hour
sleep 1800
echo "Okay, we ran for ~30 minutes, we PASS, killing remaining processes." | tee -a $OUTPUTFILE
killall -HUP pthread-read-and-fork
umount /huge
echo $nr_huge_old > /proc/sys/vm/nr_hugepages
# if we didn't panic, we have success...
report_result $TEST PASS

exit 0
