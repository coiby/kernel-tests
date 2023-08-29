#!/bin/sh

# Source the common test script helpers
. ../../kernel-include/runtest.sh
source /etc/os-release

RHEL_X=$(echo $VERSION_ID | cut -d. -f1)

CUR_TIME=$(date --date="$(date --utc)" +%s)
# control where to log debug messages to:
# devnull = 1 : log to /dev/null
# devnull = 0 : log to file specified in ${DEBUGLOG}
devnull=0

if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
fi

# Create debug log
DEBUGLOG=`mktemp -p /mnt/testarea -t DeBug.XXXXXX`

if [ -z "$OUTPUTFILE" ]; then
        export OUTPUTFILE=`mktemp /mnt/testarea/tmp.XXXXXX`
fi
touch $OUTPUTFILE

# Set a "well known" log name, so if the localwatchdog triggers
#  we can still file OUTPUTFILE and get some results.
if [ -h /mnt/testarea/current.log ]; then
        ln -sf $OUTPUTFILE /mnt/testarea/current.log
else
        ln -s $OUTPUTFILE /mnt/testarea/current.log
fi

# locking to avoid races
lck=$OUTPUTDIR/$(basename $0).lck

# Functions

# Log a message to the ${DEBUGLOG} or to /dev/null
function DeBug ()
{
    local msg="$1"
    local timestamp=$(date '+%F %T')
    if [ "$devnull" = "0" ]; then
        (
            flock -x 200 2>/dev/null
            echo -n "${timestamp}: " >>$DEBUGLOG 2>&1
            echo "${msg}" >>$DEBUGLOG 2>&1
        ) 200>$lck
    else
        echo "${msg}" >/dev/null 2>&1
    fi
}

function RHTSAbort ()
{
    # Abort the rhts recipe if we are running the wrong kernel
    DeBug "Abort recipe"
    rhts-abort -t recipe
}

function SysReport ()
{
    DeBug "Enter SysReport"
    grep -q "release 3 " /etc/redhat-release
    if [ $? -eq 0 ]; then
        modarg=-d
        modarg2=
    else
        modarg="-F description"
        modarg2="-F version"
    fi
    sysnode=$(/bin/uname -n)
    syskernel=$(/bin/uname -r)
    sysmachine=$(/bin/uname -m)
    sysprocess=$(/bin/uname -m)
    sysuname=$(/bin/uname -a)
    sysswap=$(/usr/bin/free -m | /bin/awk '{if($1=="Swap:") {print $2,"MB"}}')
    sysmem=$(/usr/bin/free -m | /bin/awk '{if($1=="Mem:") {print $2,"MB"}}')
    syscpu=$(/bin/cat /proc/cpuinfo | /bin/grep processor | wc -l)
# Bios Info
    biosVendor=$(dmidecode --type=0 | /bin/grep -i vendor | /bin/awk -F: '{print $2}')
    biosVersion=$(dmidecode --type=0 | /bin/grep -i version | /bin/awk -F: '{print $2}')
    biosRelease=$(dmidecode --type=0 | /bin/grep -i release | /bin/awk -F: '{print $2}')
    biosRevision=$(dmidecode --type=0 | /bin/grep -i revision | /bin/awk -F: '{print $2}')
#
    syslspci=$(/sbin/lspci -nnD > $OUTPUTDIR/lspci.$kernbase)
    if [ -f /etc/fedora-release ]; then
        sysrelease=$(/bin/cat /etc/fedora-release)
    else
        sysrelease=$(/bin/cat /etc/redhat-release)
    fi
    syscmdline=$(/bin/cat /proc/cmdline)
    sysnmiint=$(/bin/cat /proc/interrupts | /bin/grep -i nmi)
    sysmodprobe=$(/bin/cat /etc/modprobe.conf > $OUTPUTDIR/modprobe.$kernbase)
    for x in $(/sbin/lsmod | /bin/cut -f1 -d" " 2>/dev/null | /bin/grep -v Module 2>/dev/null ); do
        echo "Checking module information $x:" >> $OUTPUTDIR/modinfo.$kernbase
        /sbin/modinfo $modarg $x >> $OUTPUTDIR/modinfo.$kernbase
        if [ -n "$modarg2" ]; then
            /sbin/modinfo $modarg2 $x >> $OUTPUTDIR/modinfo.$kernbase
        fi
    done
    if [ -x /usr/sbin/sestatus ]; then
        syssestatus=$(/usr/sbin/sestatus >> $OUTPUTDIR/selinux.$kernbase)
    fi
    if [ -x /usr/sbin/xm ]; then
        syshypervisor=$(/usr/sbin/xm info >> $OUTPUTDIR/hypervisor.$kernbase)
    fi
    if [ -x /usr/sbin/semodule ]; then
        echo "********* SELinux Module list **********" >> $OUTPUTDIR/selinux.$kernbase
        syssemodulelist=$(/usr/sbin/semodule -l >> $OUTPUTDIR/selinux.$kernbase)
    fi

    sysderror=$(/bin/cat $OUTPUTDIR/boot.$kernbase | grep -i error | grep -v BIOS >> $OUTPUTDIR/derror.$kernbase)
    sysderror1=$(/bin/grep -i collision $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/derror.$kernbase)
    sysderror2=$(/bin/grep -i fail $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/derror.$kernbase)
    sysderror3=$(/bin/grep -i temperature $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/derror.$kernbase)
    sysderror4=$(/bin/grep BUG: $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/derror.$kernbase)
    sysderror5=$(/bin/grep INFO: $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/derror.$kernbase)
    sysderror6=$(/bin/grep FATAL: $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/derror.$kernbase)
    sysderror7=$(/bin/grep WARNING: $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/derror.$kernbase)
    sysderror8=$(/bin/grep -i "command not found" $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/derror.$kernbase)
    sysderror9=$(/bin/cat $OUTPUTDIR/boot.$kernbase | grep avc: | grep -v granted >> $OUTPUTDIR/avcerror.$kernbase)
    sysderror10=$(/bin/grep -i "Unknown symbol" $OUTPUTDIR/boot.$kernbase >> $OUTPUTDIR/serror.$kernbase)

    echo "********** System Information **********" >> $OUTPUTFILE
    echo "Hostname                = $sysnode"       >> $OUTPUTFILE
    echo "Kernel Version          = $syskernel"     >> $OUTPUTFILE
    echo "Machine Hardware Name   = $sysmachine"    >> $OUTPUTFILE
    echo "Processor Type          = $sysprocess"    >> $OUTPUTFILE
    echo "uname -a output         = $sysuname"      >> $OUTPUTFILE
    echo "Swap Size               = $sysswap"       >> $OUTPUTFILE
    echo "Mem Size                = $sysmem"        >> $OUTPUTFILE
    echo "Number of Processors    = $syscpu"        >> $OUTPUTFILE
    echo "System Release          = $sysrelease"    >> $OUTPUTFILE
    echo "Command Line            = $syscmdline"    >> $OUTPUTFILE
    echo "System NMI Interrupts   = $sysnmiint"     >> $OUTPUTFILE
    echo "*********** BIOS Information ***********" >> $OUTPUTFILE
    echo "Vendor                  = $biosVendor"    >> $OUTPUTFILE
    echo "Version                 = $biosVersion"   >> $OUTPUTFILE
    echo "Release                 = $biosRelease"   >> $OUTPUTFILE
    echo "Revision                = $biosRevision"  >> $OUTPUTFILE
    echo "**************** LSPCI *****************" >> $OUTPUTFILE
    /bin/cat $OUTPUTDIR/lspci.$kernbase             >> $OUTPUTFILE
    echo "*************** Modprob ****************" >> $OUTPUTFILE
    /bin/cat $OUTPUTDIR/modprobe.$kernbase          >> $OUTPUTFILE
    echo "********** Module Information **********" >> $OUTPUTFILE
    /bin/cat $OUTPUTDIR/modinfo.$kernbase           >> $OUTPUTFILE
    if [ -x /usr/sbin/sestatus ]; then
        echo "************ SELinux Status ************" >> $OUTPUTFILE
        /bin/cat $OUTPUTDIR/selinux.$kernbase       >> $OUTPUTFILE
    fi
    echo "********** Interfaces Information **********" > ifcinfo
    echo "-- /etc/resolv.conf --" >> ifcinfo
    cat /etc/resolv.conf >> ifcinfo
    echo "-- END of /etc/resolv.conf --" >> ifcinfo
    echo "ip a" >> ifcinfo
    ip a 2>&1 >> ifcinfo
    echo "ip route" >> ifcinfo
    ip route 2>&1 >> ifcinfo
    echo "ip -6 route" >> ifcinfo
    ip -6 route 2>&1 >> ifcinfo
    local interfaces=`ip link show | grep '^[0-9]\+' | sed 's/^[0-9]\+: \([a-zA-Z0-9]\+\):.*/\1/'`
    for i in $interfaces; do
        echo "ethtool -i $i" >> ifcinfo
        ethtool -i $i 2>&1 >> ifcinfo
    done
    cat ifcinfo >> $OUTPUTFILE
    cat ifcinfo > /dev/console
    if [ -x /usr/sbin/xm ]; then
        echo "*********** Hypervisor info ************" >> $OUTPUTFILE
        /bin/cat $OUTPUTDIR/hypervisor.$kernbase     >> $OUTPUTFILE
    fi
    FAILURE=FALSE
    # Check dmesg log for issues
    dresult_count=0
    if [ -s $OUTPUTDIR/derror.$kernbase ]; then
        dresult_count=$(/usr/bin/wc -l $OUTPUTDIR/derror.$kernbase | awk '{print $1}')
        echo "******** Potential Issues dmesg ********" >> $OUTPUTFILE
        /bin/cat $OUTPUTDIR/derror.$kernbase        >> $OUTPUTFILE
    fi
    # Check dmesg log for failures
    if [ -s $OUTPUTDIR/serror.$kernbase ]; then
        dresult_count=$(/usr/bin/wc -l $OUTPUTDIR/serror.$kernbase | awk '{print $1}')
        echo "********** Failures in dmesg ***********" >> $OUTPUTFILE
        /bin/cat $OUTPUTDIR/serror.$kernbase        >> $OUTPUTFILE
        FAILURE=TRUE
    fi
    # Check dmesg log for avc failures
    if [ -s $FILEAREA/avcerror.$kernbase ]; then
        echo "********* SElinux AVC Failures *********" >> $OUTPUTFILE
        /bin/cat $FILEAREA/avcerror.$kernbase       >> $OUTPUTFILE
        FAILURE=TRUE
    fi
    echo "******** End System Information ********" >> $OUTPUTFILE
    if [ -s $OUTPUTDIR/derror.$kernbase -o -s $OUTPUTDIR/serror.$kernbase -o -s $OUTPUTDIR/avcerror.$kernbase ]; then
        # why is $dresult_count padded with 6 trailing 0s?  dropping them because
        # this is triggering https://bugzilla.redhat.com/show_bug.cgi?id=1600281
        #result_count=$(/usr/bin/printf "%03d%03d%03d\n" $dresult_count 0 0)
        result_count=$(/usr/bin/printf "%03d\n" $dresult_count)
        if [ $FAILURE = TRUE ]; then
            report_result $TEST/Sysinfo FAIL $result_count
        else
            report_result $TEST/Sysinfo PASS $result_count
        fi
    else
        report_result $TEST/Sysinfo PASS 0
    fi
    DeBug "Exit SysReport"
}

function DiffDmesg ()
{
    DeBug "Enter DiffDmesg"
    DMESGDIFFLOG=`mktemp -p /mnt/testarea -t DMSGDIFF.XXXXXX`
    filelist=`ls $OUTPUTDIR/boot.*`
    hit=0
    for l in $filelist ; do
        hit=`expr $hit + 1`
        export FILE$hit=$l
        DeBug "$FILE$l"
    done
    echo "
===================================================================
diff -u $FILE1 $FILE2
===================================================================" | tee -a $DMESGDIFFLOG
    /usr/bin/diff -u $FILE1 $FILE2 | tee -a $DMESGDIFFLOG
    DeBug "/usr/bin/diff -u $FILE1 $FILE2"
    sleep 3
    SubmitLog $DMESGDIFFLOG
    DeBug "Exit DiffDmesg"
}

function DiffLspci ()
{
    DeBug "Enter DiffLspci"
    LSPCIDIFFLOG=`mktemp -p /mnt/testarea -t LSPCIDIFF.XXXXXX`
    filelist=`ls $OUTPUTDIR/lspci.*`
    hit=0
    for l in $filelist ; do
        hit=`expr $hit + 1`
        export FILE$hit=$l
        DeBug "$FILE$l"
    done
    echo "
===================================================================
diff -u $FILE1 $FILE2
===================================================================" | tee -a $LSPCIDIFFLOG
    /usr/bin/diff -u $FILE1 $FILE2 | tee -a $LSPCIDIFFLOG
    DeBug "/usr/bin/diff -u $FILE1 $FILE2"
    sleep 3
    SubmitLog $LSPCIDIFFLOG
    DeBug "Exit DiffLspci"
}

function report_result ()
{
    rhts-report-result "$1" "$2" "$OUTPUTFILE" "$3"
}

function RprtRslt ()
{
    ONE=$1
    TWO=$2
    THREE=$3

    # File the results in the database
    report_result $ONE $TWO $THREE

    if [ "$TWO" == "FAIL" ]; then
        SubmitLog $DEBUGLOG
    fi
}

function SubmitLog ()
{
    LOG=$1
    rhts_submit_log -l $LOG
}

function XendLogging ()
{
    XENDCONF=/etc/sysconfig/xend
    DeBug "Enter XendLogging"
    if [ -e $XENDCONF ]; then
        DeBug "$XENDCONF exists"
        sed -i 's/#XENCONSOLED_LOG_HYPERVISOR=no/XENCONSOLED_LOG_HYPERVISOR=yes/g' $XENDCONF
        sed -i 's/#XENCONSOLED_LOG_GUESTS=no/XENCONSOLED_LOG_GUESTS=yes/g' $XENDCONF
        sed -i 's/#XENCONSOLED_LOG_DIR/XENCONSOLED_LOG_DIR/g' $XENDCONF
    fi
    DeBug "Exit XendLogging"
}

function LogBootloaderConfig ()
{
    conf_files="/boot/grub2/grub.cfg /boot/grub/grub.conf /boot/efi/efi/redhat/elilo.conf
    /boot/etc/yaboot.conf /etc/yaboot.conf /etc/zipl.conf
    /boot/loader/entries/*"

    for conf_file in $conf_files; do
        if [ -f $conf_file ]; then
            echo "----- $conf_file -----" | tee -a $DEBUGLOG
            cat $conf_file | tee -a $DEBUGLOG
            echo "----- $conf_file END -----" | tee -a $DEBUGLOG
        fi
    done
}

function SelectKernel ()
{
    DeBug "Enter SelectKernel"
    VR=$1
    EXTRA=$2
    DeBug "VR=$VR EXTRA=$EXTRA"

    # If not version or Extra selected then choose the latest installed version
    if [ -z "$EXTRA" -a -z "$VR" ]; then
        DeBug "ERROR: missing args"
        return 1
    fi

    # Workaround for RT kernels
    if [[ "$RT_REQUESTED" = "true" ]]; then
        DeBug "EXTRA=$EXTRA"
        if [[ "$RT_UNIFIED" == "true" ]]; then
            # Unified tree kernel-rt inherits kernel NVR and
            # appends "+rt" or "+rt-debug"
            if [[ "$RT_DEBUG" == "true" ]]; then
                EXTRA="rt-debug"
            else
                EXTRA="rt"
            fi
        else
            # Non-unified tree kernel-rt has unique NVR and
            # only appends "+debug" for kernel-rt-debug
            if [[ "$RT_DEBUG" == "true" ]]; then
                EXTRA="debug"
            else
                EXTRA=""
            fi
        fi
    fi

    # Workaround for UP kernel spec file
    if [ "$EXTRA" = "up" ]; then
        DeBug "EXTRA=$EXTRA"
        EXTRA=""
    fi

    echo "***** Attempting to switch boot kernel to ($VR$EXTRA) *****" | tee -a $OUTPUTFILE
    DeBug "Attempting to switch boot kernel to ($VR$EXTRA)"

    # if we have grubby, then let's use that
    if command -v grubby >/dev/null 2>&1; then
        SelectKernelGrubby $VR $EXTRA
        ret=$?
    else
        SelectKernelLegacy $VR $EXTRA
        ret=$?
    fi

    sync
    sleep 5
    DeBug "Exit SelectKernel"
    return $ret
}

# Bug 798577 - ppc64: grubby/new-kernel-pkg fails to install new kernel
# There seem to be 2 issues, one in anaconda, one in grubby
function WorkaroundBug798577 ()
{
    local VR=$1
    local EXTRA=$2
    local vmlinuz=$3

    DeBug "WorkaroundBug798577: start <$VR> <$EXTRA> <$vmlinuz>"
    uname -r | grep ppc64
    if [ $? -ne 0 ]; then
        DeBug "WorkaroundBug798577: this is not ppc64"
        return 0
    fi

    cat /etc/redhat-release | grep "release 7"
    if [ $? -ne 0 ]; then
        DeBug "WorkaroundBug798577: this is not RHEL7"
        return 0
    fi

    local initrd=$(rpm -ql $testkernbase.$kernarch | grep -e /initramfs-$VR | grep "$EXTRA" | awk '{print length"\t"$0}' | sort -n | cut -f2- | head -1)
    DeBug "WorkaroundBug798577: vmlinuz=$vmlinuz"
    DeBug "WorkaroundBug798577: initrd=$initrd"

    if [ -n "$vmlinuz" -a -n "$initrd" ]; then
        sed -i 's/image=vmlinu/image=\/vmlinu/' /etc/yaboot.conf
        DeBug "/sbin/new-kernel-pkg --package kernel --install $VR.ppc64 --initrdfile=$initrd"
        /sbin/new-kernel-pkg --package kernel --install $VR.ppc64 --initrdfile=$initrd

        grubby --set-default "$vmlinuz"
        cp -f /etc/yaboot.conf /boot/etc/yaboot.conf
        ybin -v

        default_vmlinuz=$(grubby --default-kernel)
        DeBug "WorkaroundBug798577: grubby --default-kernel: $default_vmlinuz"
    fi

    DeBug "WorkaroundBug798577: end"
}

function update_console ()
{
    # Xen uses com1 for ttyS0 and com2 for ttyS1
    # com1 might be setup automatically *if* you installed xen from anaconda
    # com2 is never set up correctly by anaconda.

    # Take first serial console entry
    console=$(awk '/console=ttyS/{for(i=1;i<=NF;++i)if($i~/console=ttyS[^ ]*/)print $i; exit}' /etc/grub.conf)
    # Find our defult kernel
    default_kernel=$(grubby --default-kernel)
    # Get the serial settings and order them for XEN
    settings=$(echo $console |perl -pe 's/.*,([0-9]+)([neo])?([5678])?1?/$1,$3${2}1/')

    DeBug $console
    if echo $console | grep -q ttyS0 ; then
       # Configure com1, may already be done if installed xen from anaconda
       DeBug "ttyS0 = com1"
       grubby --mbargs com1=$settings --update-kernel=$default_kernel
    elif echo $console | grep -q ttyS1 ; then
       # Configure com2, change linux kernel console=ttyS1 to console=ttyS0
       DeBug "ttyS1 = com2"
       ttyS0=$(echo $console | sed -e 's/ttyS1/ttyS0/')
       grubby --remove-mbargs com1=$settings --update-kernel=$default_kernel
       grubby --mbargs com2=$settings --update-kernel=$default_kernel
       grubby --mbargs console=com2L --update-kernel=$default_kernel
       grubby --remove-args $console --update-kernel=$default_kernel
       grubby --args $ttyS0 --update-kernel=$default_kernel
    else
       DeBug "Non-standard serial console"
    fi
}

function SelectKernelGrubby ()
{
    DeBug "Enter SelectKernelGrubby"
    VR=$1
    EXTRA=$2
    DeBug "VR=$VR EXTRA=$EXTRA"

    # We can only have one kernel on arm right now and grubby is busted
    # until bz 751608 is fixed.
    if [ "${ARCH}" = "armhfp" -o "${ARCH}" = "arm" ]; then
        return 0
    fi

    # match vmlinuz with $VR and $EXTRA, take first shortest match
    # try to find vmlinuz in kernel and kernel-core packages
    echo -e "SelectKernelGrubby - looking for file \"vmlinu.-$VR\"\nin the file-list for the rpm package \"$testkername-$KERNELARGVERSION.$kernarch\""
    rpm -ql $testkername-$KERNELARGVERSION.$kernarch | grep -e /vmlinu.-$VR | grep "$EXTRA" > ./vmlinuz_candidates
    rpm -ql $testkername-core-$KERNELARGVERSION.$kernarch | grep -e /vmlinu.-$VR | grep "$EXTRA" >> ./vmlinuz_candidates
    if [[ ! -s ./vmlinuz_candidates ]] ; then
      echo "SelectKernelGrubby - ./vmlinuz_candidates is empty. Falling back to search for '/vmlinuz-'"
      rpm -ql $testkername-$KERNELARGVERSION.$kernarch | grep -e /vmlinuz- | grep "$EXTRA" > ./vmlinuz_candidates
      rpm -ql $testkername-core-$KERNELARGVERSION.$kernarch | grep -e /vmlinuz- | grep "$EXTRA" >> ./vmlinuz_candidates
    fi
    echo "vmlinuz candidates: " | tee -a $OUTPUTFILE
    cat ./vmlinuz_candidates | tee -a $OUTPUTFILE

    local vmlinuz=$(cat ./vmlinuz_candidates | awk '{print length"\t"$0}' | sort -n | cut -f2- | head -1)
    echo "vmlinuz picked as best match: $vmlinuz" | tee -a $OUTPUTFILE
    rm -f ./vmlinuz_candidates

    for grub_cfg in "/etc/grub.conf" "/etc/grub2.cfg" /boot/loader/entries/* ; do
        if [ -e "$grub_cfg" -a -n "${vmlinuz#/boot}" ]; then
            grep -q "${vmlinuz#/boot}" "$grub_cfg"
            if [ $? -eq 0 ]; then
                echo "$vmlinuz found in $grub_cfg" | tee -a $OUTPUTFILE
            else
                echo "Error: $vmlinuz not found in $grub_cfg" | tee -a $OUTPUTFILE
            fi
        fi
    done

    rm -f /mnt/testarea/kernelinstall_kernel_to_boot
    if [ -n "$vmlinuz" ]; then
        if [[ $vmlinuz =~ .*vmlinu.-(.*) ]]; then
          DeBug "The NAME-VERSION-RELEASE for kernel to boot is ${BASH_REMATCH[1]}"
          echo "${BASH_REMATCH[1]}" > /mnt/testarea/kernelinstall_kernel_to_boot
        fi
        echo "Running grubby --set-default $vmlinuz"
        grubby --set-default "$vmlinuz"
        ret=$?
        DeBug "grubby --set-default $vmlinuz returned: $ret"
        default_vmlinuz=$(grubby --default-kernel)
        echo "Default boot kernel reported by grubby --default-kernel: '$default_vmlinuz'"
        DeBug "grubby --default-kernel: $default_vmlinuz"
        LogBootloaderConfig

        if [ "$default_vmlinuz" == "$vmlinuz" ]; then
            DeBug "grubby reports correct kernel as default: $default_vmlinuz"
        else
            DeBug "grubby reports default kernel as: $default_vmlinuz, expected: $vmlinuz"
            DeBug "trying WorkaroundBug798577"
            WorkaroundBug798577 "$VR" "$EXTRA" "$vmlinuz"
            LogBootloaderConfig
        fi

        if [ $ret -eq 0 ]; then
            test "${ARCH}" = "s390" -o "${ARCH}" = "s390x" && zipl
        fi
        return $ret
    fi
    DeBug "ERROR: failed to find vmlinuz in rpm: $testkernbase.$kernarch"
    return 1
}

function SelectKernelLegacy ()
{
    DeBug "Enter SelectKernelLegacy"
    VR=$1
    EXTRA=$2
    DeBug "VR=$VR EXTRA=$EXTRA"

    grub_file=/boot/grub/grub.conf

    if [ -f $grub_file ]; then
        DeBug "Using: $grub_file"
        COUNT=0
        DEFAULT=undefined
        for i in $(grep '^title' $grub_file | sed -e 's/.*(\(.*\)).*/\1/' -e "s/\.$(uname -m)*.//g"); do
            DeBug "COUNT=$COUNT VR=$VR EXTRA=$EXTRA i=$i"
            if [ "$VR$EXTRA" = "$i" ]; then
                DEFAULT=$COUNT;
            fi
            COUNT=$(expr $COUNT + 1)
        done
        if [ $DEFAULT != "undefined" ]; then
            DeBug "DEFAULT=$DEFAULT"
            /bin/ed -s $grub_file <<EOF
/default/
d
i
default=$DEFAULT
.
w
q
EOF
        fi
        DeBug "$grub_file"
        cat $grub_file | tee -a $DEBUGLOG
    fi

    elilo_file=/boot/efi/efi/redhat/elilo.conf

    if [ -f $elilo_file ]; then
        DeBug "Using: $elilo_file"
        DEFAULT=$(grep -A 2 "image=vmlinuz-$VR$EXTRA$" $elilo_file | awk -F= '/label=/ {print $2}')
        DeBug "DEFAULT=$DEFAULT"
        if [ -n "$DEFAULT" ]; then
            DeBug "DEFAULT=$DEFAULT"
            /bin/ed -s $elilo_file <<EOF
/default/
d
i
default=$DEFAULT
.
w
q
EOF
        fi
        DeBug "$elilo_file"
        cat $elilo_file | tee -a $DEBUGLOG
    fi

    yaboot_file=/boot/etc/yaboot.conf

    if [ -f $yaboot_file ] ; then
        DeBug "Using: $yaboot_file"
        grep vmlinuz $yaboot_file
        if [ $? -eq 0 ] ; then
            VM=z
        else
            VM=x
        fi
        DeBug "VM=$VM"
        DEFAULT=$(grep -A 1 "image=/vmlinu$VM-$VR.*$EXTRA" $yaboot_file | awk -F= '/label=/ {print $2}')
        DeBug "DEFAULT=$DEFAULT"
        if [ -n "$DEFAULT" ] ; then
            sed -i 's/label=linux/label=orig-linux/g' $yaboot_file
            sed -i 's/label='$DEFAULT'/label=linux/g' $yaboot_file
            DeBug "DEFAULT=$DEFAULT"
            grep -q label=linux $yaboot_file
            if [ $? -ne 0 ] ; then
                sed -i 's/label=orig-linux/label=linux/g' $yaboot_file
                DeBug "Reverted back to original kernel"
            fi
        fi
        DeBug "$yaboot_file"
        cat $yaboot_file | tee -a $DEBUGLOG
    fi

    zipl_file=/etc/zipl.conf

    if [ -f $zipl_file ] ; then
        DeBug "Using: $zipl_file"
        DEFAULT=$(grep "image=/boot/vmlinuz-$VR.*$EXTRA" $zipl_file | awk -Fvmlinuz- '/vmlinuz/ {printf "%.15s\n",$2}')
        DeBug "DEFAULT=$DEFAULT"
        if [ -n "$DEFAULT" ] ; then
            DeBug "$VR$EXTRA"
            tag=$(grep "\[$DEFAULT\]" $zipl_file)
            DeBug "tag=$tag"
            if [ -z "$tag" ] ; then
                # This was added because BZ 426992 was fixed
                DEFAULT=$(grep "image=/boot/vmlinuz-$VR.*$EXTRA" $zipl_file | awk -Fvmlinuz- '/vmlinuz/ {printf "%s\n",$2}')
                DeBug "Second DEFAULT=$DEFAULT"
                tag=$(grep "\[$DEFAULT\]" $zipl_file)
                DeBug "Second tag=$tag"
                if [ -z "$tag" ] ; then
                    DeBug "Setting it back to default"
                    DEFAULT=linux
                fi
            fi
            /bin/ed -s $zipl_file <<EOF
/default=/
d
i
default=$DEFAULT
.
w
q
EOF
            zipl
        fi
        DeBug "$zipl_file"
        cat $zipl_file | tee -a $DEBUGLOG
    fi
    return 0
}

function CheckKernel ()
{
    DeBug "Enter CheckKernel"
    KVER=$1
    KVAR=$2
    DeBug "Before KVER=$KVER KVAR=$KVAR"

    # Workaround for RT kernels
    if [[ "$RT_REQUESTED" = "true" ]]; then
        DeBug "KVAR=$KVAR"
        if [[ "$RT_UNIFIED" == "true" ]]; then
            # Unified tree kernel-rt inherits kernel NVR and
            # appends "+rt" or "+rt-debug"
            if [[ "$RT_DEBUG" == "true" ]]; then
                KVAR="rt-debug"
            else
                KVAR="rt"
            fi
        else
            # Non-unified tree kernel-rt has unique NVR and
            # only appends "+debug" for kernel-rt-debug
            if [[ "$RT_DEBUG" == "true" ]]; then
                KVAR="debug"
            else
                KVAR=""
            fi
        fi
    fi

    # Workaround for UP kernels
    if [[ "$KVAR" = "up" ]]; then
        DeBug "KVAR=$KVAR"
        KVAR=""
    elif [[ "$KVAR" = "64k-up" ]]; then
        KVAR="64k"
    fi

    DeBug "After KVER=$KVER KVAR=$KVAR"

    echo "Expecting $KVER$KVAR | Running $runkernel"
    if [[ "$KVER$KVAR" == "$runkernel" ]]; then
        DeBug "Requested kernel = Running kernel"
        DeBug "   $KVER$KVAR = $runkernel"
        return 0
    else
        DeBug "Requested kernel != Running kernel"
        DeBug "   $KVER$KVAR != $runkernel"
        if [[ -s /mnt/testarea/kernelinstall_kernel_to_boot ]]; then
            DeBug "This can happen with manually built kernel rpms"
            DeBug "Checking against '/mnt/testarea/kernelinstall_kernel_to_boot' file"
            NVR=$(cat /mnt/testarea/kernelinstall_kernel_to_boot)
            rm -f /mnt/testarea/kernelinstall_kernel_to_boot
            DeBug "Target NVR stored in '/mnt/testarea/kernelinstall_kernel_to_boot' file: '${NVR}'"
            if [ "$NVR$KVAR" != "$runkernel" ]; then
                DeBug "Stored NVR does not match running kernel"
                DeBug "$NVR$KVAR != $runkernel"
                 return 1
            else
                DeBug "Stored NVR matches running kernel"
                DeBug "$NVR$KVAR == $runkernel"
                return 0
            fi
        else
            # File /mnt/testarea/kernelinstall_kernel_to_boot does not exist (and Requested kernel != Running kernel)
            return 1
        fi
    fi
    DeBug "Exit CheckKernel"
}

function AddTmpRepo ()
{
    DeBug "Enter AddTmpRepo"
    if [[ "${KERNELARGTMPREPO}xx" != "xx" ]]; then
        local repo_id=$(echo ${KERNELARGTMPREPO} | md5sum | cut -b -8)

        tmprepofile=/etc/yum.repos.d/kernel_install_temporary_${repo_id}.repo
        if ! >${tmprepofile}; then
            echo "***** Cannot create file \"${tmprepofile}\". No new repositories will be added. *****" | tee -a $OUTPUTFILE
            unset tmprepofile
            return
        else
            echo "***** AddTmpRepo: New repositories will be added to file  \"${tmprepofile}\". *****" | tee -a $OUTPUTFILE
        fi

        local counter="0"
        for URL in ${KERNELARGTMPREPO}; do
            echo "[tmp-${repo_id}-${counter}]"   >> ${tmprepofile}
            echo "name=tmp-${repo_id}-${counter}" >> ${tmprepofile}
            echo "baseurl=${URL}"                 >> ${tmprepofile}
            echo "enabled=1"                      >> ${tmprepofile}
            echo "gpgcheck=0"                     >> ${tmprepofile}
            echo "skip_if_unavailable=1"          >> ${tmprepofile}
            echo                                  >> ${tmprepofile}
            (( counter++ ))
        done
        SubmitLog ${tmprepofile}
    fi
    DeBug "Exit AddTmpRepo"
}

function AddPermRepo ()
{
    DeBug "Enter AddPermRepo"
    if [[ "${KERNELARGPERMREPO}xx" != "xx" ]]; then
        local repo_id=$(echo ${KERNELARGPERMREPO} | md5sum | cut -b -8)

        permrepofile=/etc/yum.repos.d/kernel_install_permanent_${repo_id}.repo
        if ! >${permrepofile}; then
            echo "***** Cannot create file \"${permrepofile}\". No new repositories will be added. *****" | tee -a $OUTPUTFILE
            unset permrepofile
            return
        else
            echo "***** AddPermRepo: New repositories will be added to file  \"${permrepofile}\". *****" | tee -a $OUTPUTFILE
        fi

        local counter="0"
        for URL in ${KERNELARGPERMREPO}; do
            echo "[permanent-${repo_id}-${counter}]"    >> ${permrepofile}
            echo "name=permanent-${repo_id}-${counter}" >> ${permrepofile}
            echo "baseurl=${URL}"                       >> ${permrepofile}
            echo "enabled=1"                            >> ${permrepofile}
            echo "gpgcheck=0"                           >> ${permrepofile}
            echo "skip_if_unavailable=1"                >> ${permrepofile}
            echo                                        >> ${permrepofile}
            (( counter++ ))
        done
        SubmitLog ${permrepofile}
    fi
    DeBug "Exit AddPermRepo"
}

function DisableTmpRepo ()
{
    DeBug "Enter DisableTmpRepo"
    if [[ "${tmprepofile}xx" != "xx" ]]; then
        if [[ -w ${tmprepofile} ]]; then
            sed -i 's/enabled=1/enabled=0/g' ${tmprepofile}
        fi
    fi
    DeBug "Exit DisableTmpRepo"
}

function YumInstallKernel ()
{
    DeBug "Enter YumInstallPackage"
    echo "***** Install kernel via yum $testkernbase.$kernarch *****" | tee -a $OUTPUTFILE
    DeBug "Yum install $testkernbase.$kernarch"
    $yumcmd list all --showduplicates $testkernbase.$kernarch | grep -q $testkername.$kernarch
    if [ "$?" -eq "0" ]; then
        # Install the kernel from yum repo
        $yumcmd -y install $testkernbase.$kernarch
        ret=$?
        if [ "$ret" -ne "0" ] && $yumcmd install --help | grep allowerasing >/dev/null; then
            # Try again using --allowerasing.  If this succeeds, report a warning
            $yumcmd -y install --allowerasing $testkernbase.$kernarch
            ret=$?
            if [ "$ret" -eq "0" ]; then
                echo "***** Yum install only succeeded due to use of --allowerasing *****" | tee -a $OUTPUTFILE
                DeBug "WARN: Yum required --allowerasing to install kernel"
                report_result $TEST/Yum_AllowErasing_Needed WARN 0
            fi
        fi
        if [ "$ret" -ne "0" ]; then
            echo "***** Yum returned an error while trying to install $testkernbase.$kernarch *****" | tee -a $OUTPUTFILE
            DeBug "Exit YumInstallPackage FAIL 3 (YUM exited with a failure)"
            return 3
        else
            # Check to see if the kernel is now installed, using yum
            $yumcmd list installed $testkernbase.$kernarch | grep -q installed
            if [ "$?" -ne "0" ]; then
                # Double check, this time using rpm
                rpm -qa --queryformat '%{name}-%{version}-%{release}.%{arch}\n' | grep -q $testkernbase.$kernarch
                if [ "$?" -ne "0" ]; then
                    echo "***** Failed to find $testkernbase.$kernarch in installed *****" | tee -a $OUTPUTFILE
                    DeBug "Exit YumInstallPackage FAIL 4 (Thought we installed but can't find it)"
                    return 4
                fi
            fi
        fi
        # Install kernel-devel package from yum repo
        echo "***** Install kernel-devel package via yum $testkerndevel.$kernarch *****" | tee -a $OUTPUTFILE
        DeBug "Yum install $testkerndevel.$kernarch"
        $yumcmd -y install $testkerndevel.$kernarch
        if [ "$?" -ne "0" ]; then
            echo "***** Yum returned an error while trying to install $testkerndevel.$kernarch  *****" | tee -a $OUTPUTFILE
            DeBug "Exit YumInstallPackage FAIL 5 (YUM exited with a failure)"
        fi
        # Install kernel-modules-extra if running on RHEL8+
        if echo "$KERNELARGVERSION" | grep -Eq '\.(el8|elrdy|el9)'; then
            if [ "$KERNELARGEXTRAMODULES" == "1" ]; then
                echo "***** Install kernel-modules-extra package via yum ${testkername}-modules-extra-${KERNELARGVERSION}.$kernarch *****" | tee -a $OUTPUTFILE
                $yumcmd -y install ${testkername}-modules-extra-${KERNELARGVERSION}.$kernarch
            fi
        fi
    else
        DeBug "Exit YumInstallPackage FAIL 6 (Can't find kernel in repo)"
        return 6
    fi
    DeBug "Exit YumInstallPackage SUCCESS"
    return 0
}

function BrewInstallKernel ()
{
    # Is the kernel available for install from a BREW
    DeBug "Enter BrewInstallPackage"
    # install kernel-firmware first if there is one.
    if curl -s $httpbase/noarch/$testkernfirmware.noarch.rpm -o /dev/null -f; then
        kernfwprpm="$httpbase/noarch/$testkernfirmware.noarch.rpm"
    elif curl -s $archbase/noarch/$testkernfirmware.noarch.rpm -o /dev/null -f; then
        kernfwprpm="$archbase/noarch/$testkernfirmware.noarch.rpm"
    fi
    yum -y localinstall --nogpgcheck $kernfwprpm
    DeBug "$httpbase/$kernarch/$testkernbase.$kernarch.rpm"
    echo "***** Install kernel via BREW $testkernbase.$kernarch.rpm *****" | tee -a $OUTPUTFILE
    if curl -s $httpbase/$kernarch/$testkernbase.$kernarch.rpm -o /dev/null -f; then
       yum --version > /dev/null 2>&1
       if [ $? -eq 0 ]; then
          DeBug "Attempting to install kernel using YUM"
          # Yum does not work with http urls on RHEL5, so to avoid branching
          # just download the kernel rpms and install
          pushd /tmp
          curl -L -s $httpbase/$kernarch/$testkernbase.$kernarch.rpm -O
          curl -L -s $httpbase/$kernarch/$testkerndevel.$kernarch.rpm -O
          popd
          # RHEL8 kernels are now provided by the meta package kernel which
          # requires kernel-core and kernel-modules packages
          if echo "$KERNELARGVERSION" | grep -Eq '\.(el8|elrdy|el9)'; then
             testkerncore=$testkername-core-$KERNELARGVERSION
             testkernmodules=$testkername-modules-$KERNELARGVERSION
             testkernmodules_core=$testkername-modules-core-$KERNELARGVERSION
             curl -L -s $httpbase/$kernarch/$testkerncore.$kernarch.rpm -O
             curl -L -s $httpbase/$kernarch/$testkernmodules.$kernarch.rpm -O
             if curl -L -s --head -f -o /dev/null $httpbase/$kernarch/$testkernmodules_core.$kernarch.rpm; then
                 curl -L -s $httpbase/$kernarch/$testkernmodules_core.$kernarch.rpm -O
             fi
             if test -f $testkernmodules_core.$kernarch.rpm; then
                 testkernelmodules_rpms="$testkernmodules.$kernarch.rpm $testkernmodules_core.$kernarch.rpm"
             else
                 testkernelmodules_rpms="$testkernmodules.$kernarch.rpm"
             fi
             $yumcmd -y localinstall --nogpgcheck \
                 /tmp/$testkernbase.$kernarch.rpm \
                 $testkerncore.$kernarch.rpm \
                 $testkernelmodules_rpms
             rpm -qa | grep $testkerncore || rpm -ivh \
                 /tmp/$testkernbase.$kernarch.rpm \
                 $testkerncore.$kernarch.rpm \
                 $testkernelmodules_rpms --force --nodeps
             rpm -qa | grep $testkerncore

             if [ "$KERNELARGEXTRAMODULES" == "1" ]; then
                testkernmodulesextra=${testkername}-modules-extra-${KERNELARGVERSION}
                curl -L -s $httpbase/$kernarch/$testkernmodulesextra.$kernarch.rpm -O
                $yumcmd -y localinstall --nogpgcheck \
                    $testkernmodulesextra.$kernarch.rpm
             fi
          else
             $yumcmd -y localinstall --nogpgcheck /tmp/$testkernbase.$kernarch.rpm
          fi
          $yumcmd -y localinstall --nogpgcheck /tmp/$testkerndevel.$kernarch.rpm
       else
          rpm -ivh $httpbase/$kernarch/$testkernbase.$kernarch.rpm
          if [ "$?" -ne "0" ]; then
             DeBug "Forcing the rpm command --force"
             rpm -ivh --force $NoDeps $httpbase/$kernarch/$testkernbase.$kernarch.rpm
             if [ "$?" -ne "0" ]; then
                DeBug "Exit BrewInstallPackage FAIL 6"
                return 6
             fi
          fi
          rpm -ivh $httpbase/$kernarch/$testkerndevel.$kernarch.rpm
       fi
       DeBug "Exit BrewInstallPackage SUCCESS"
    elif curl -s $archbase/$kernarch/$testkernbase.$kernarch.rpm -o /dev/null -f; then
       DeBug "Installing the rpm from the kernelarchive."
       rpm -ivh $archbase/$kernarch/$testkernbase.$kernarch.rpm
       if [ "$?" -ne "0" ]; then
          DeBug "Forcing the rpm command --force"
          rpm -ivh --force $NoDeps $archbase/$kernarch/$testkernbase.$kernarch.rpm
          if [ "$?" -ne "0" ]; then
             DeBug "Exit BrewInstallPackage FAIL 6"
             return 6
          fi
       fi
       rpm -ivh $archbase/$kernarch/$testkerndevel.$kernarch.rpm
       DeBug "Exit BrewInstallPackage SUCCESS"
    else
       DeBug "can't find the package in brew ... FAIL"
       return 1
    fi
    return 0
}

function YumUpgradeKernelHeaders ()
{
    if [[ "$KERNELARGNAME" == "kernel-rt" || "$KERNELARGVARIANT" == "rt"* ]]; then
        # RT kernel does not have a kernel-rt-headers package
        echo "***** Kernel is RT: skipping kernel headers upgrade *****"
        return 0
    fi

    KERNELHEADERS=$(K_GetRunningKernelRpmSubPackageNVR headers)

    DeBug "Enter YumUpgradeKernelHeaders"
    echo "***** Upgrade $KERNELHEADERS via yum *****" | tee -a $OUTPUTFILE
    REBOOT_TIME=$(cat /mnt/testarea/kernelinstall_reboottime.log)
    DeBug "Yum upgrade $KERNELHEADERS"
    $yumcmd list all --showduplicates $KERNELHEADERS | grep -q $testkernver-$testkernrel
    if [ "$?" -eq "0" ]; then
        # Install the kernel-headers from yum repo
        $yumcmd -y upgrade $KERNELHEADERS
        if [ "$?" -ne "0" ]; then
            echo "***** Yum returned an error while trying to upgrade $KERNELHEADERS *****" | tee -a $OUTPUTFILE
            DeBug "Exit YumUpgradeKernelHeaders FAIL 3 (YUM exited with a failure)"
            return 3
        else
            # Check to see if the kernel-headers is now installed, using yum
            $yumcmd list installed $KERNELHEADERS | grep -q installed
            if [ "$?" -ne "0" ]; then
                # Double check, this time using rpm
                rpm -qa --queryformat '%{name}-%{version}-%{release}\n' | grep -q $KERNELHEADERS
                if [ "$?" -ne "0" ]; then
                    echo "***** Failed to find $KERNELHEADERS in installed *****" | tee -a $OUTPUTFILE
                    DeBug "Exit YumInstallPackage FAIL 4 (Thought we installed but can't find it)"
                    return 4
                fi
            fi
        fi
    else
        DeBug "Exit YumUpgradeKernelHeaders FAIL 5 (Can't find kernel in repo)"
        return 5
    fi
    DeBug "Exit YumUpgradeKernelHeaders SUCCESS"
    return 0
}

function DepmodChk ()
{
    DeBug "Enter DepmodChk"
    DEPCHKFILE=`mktemp /tmp/tmp.XXXXXX`
    DeBug "DEPCHKFILE=$DEPCHKFILE"
    /sbin/depmod -ae -F /boot/System.map-`uname -r` `uname -r` > $DEPCHKFILE 2>&1
    if [ -s $DEPCHKFILE ] ; then
        DeBug "$DEPCHKFILE > 0"
        total=`cat $DEPCHKFILE | wc -l`
        OUTPUTFILE=`mktemp /tmp/tmp.XXXXXX`
        echo "***** List of Warnings/Errors reported by depmod *****" | tee -a $OUTPUTFILE
        cat $DEPCHKFILE | tee -a $OUTPUTFILE
        echo "***** End of list *****" | tee -a $OUTPUTFILE
        report_result $TEST/depmod FAIL $total
    fi
    DeBug "Exit DepmodChk"
}

function NukeRepo ()
{
    DeBug "Enter NukeRepo"
    if [ -e /etc/yum.repos.d/rhel-beta.repo ] ; then
        DeBug "beta repo existed, moving it to tmp"
        mv -f /etc/yum.repos.d/rhel-beta.repo /tmp
        yum clean all
    fi
    DeBug "Exit NukeRepo"
}

fix_bootif ()
{
    local macaddr=${1}
    local IFS='-'
    macaddr=$(for i in ${macaddr} ; do echo -n $i:; done)
    macaddr=${macaddr%:}
    # strip hardware type field from pxelinux
    [ -n "${macaddr%??:??:??:??:??:??}" ] && macaddr=${macaddr#??:}
    # return macaddr with lowercase alpha characters expected by udev
    echo $macaddr | sed 'y/ABCDEF/abcdef/'
}

function workaround_bug905918 ()
{
    echo "Enter workaround_bug905918" >> $OUTPUTFILE

    cat /etc/redhat-release | grep "release 7"
    if [ $? -ne 0 ]; then
        echo "This is not RHEL7, exiting"
        return
    fi

    local cmdline=`grep "Command line" /var/log/anaconda/syslog | head -1`
    local BOOTIF=`echo $cmdline | grep -o "BOOTIF=[0-9a-zA-Z:-]\+" | sed 's/BOOTIF=//'`

    # command line
    echo $cmdline | grep "ip=" 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        echo "ip= present on command line, exiting" >> $OUTPUTFILE
        return
    fi

    # kickstart
    if [ ! -f /root/anaconda-ks.cfg ]; then
        echo "Could not find /root/anaconda-ks.cfg, exiting" >> $OUTPUTFILE
        return
    fi
    grep "^network" /root/anaconda-ks.cfg | grep device
    if [ $? -eq 0 ]; then
        echo "device= present in kickstart network option, exiting" >> $OUTPUTFILE
        return
    fi

    if [ -z "$BOOTIF" ]; then
        echo "Could not find BOOTIF in /var/log/anaconda/syslog" >> $OUTPUTFILE
        return
    fi
    BOOTIF=$(fix_bootif "$BOOTIF")
    echo "Fixed up BOOTIF: $BOOTIF" >> $OUTPUTFILE

    ip a s up | grep $BOOTIF 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
        echo "Could not find any interface with this MAC, exiting" >> $OUTPUTFILE
        return
    fi

    local ifcfg_mask="/etc/sysconfig/network-scripts/ifcfg-"
    for ifcfg in $ifcfg_mask*; do
        local ifc=`echo $ifcfg | sed "s|$ifcfg_mask||"`
        if [ "$ifc" == "lo" ]; then
            continue
        fi
        grep -l -i "$BOOTIF" $ifcfg 2>&1 >/dev/null
        if [ $? -ne 0 ]; then
            echo "Setting ONBOOT=no for $ifcfg" >> $OUTPUTFILE
            sed -i 's/ONBOOT=.*/ONBOOT=no/' $ifcfg
            restorecon $ifcfg
            echo "Turning off interface (ip link set down): $ifc" >> $OUTPUTFILE
            ip link set down $ifc
        fi
    done
    #wait for NetworkManager to process new config
    sleep 60
    date >> $OUTPUTFILE
    ls -la /etc/resolv.conf >> $OUTPUTFILE
    echo "-- /etc/resolv.conf --"
    cat /etc/resolv.conf >> $OUTPUTFILE
    echo "-- END of /etc/resolv.conf --"
    echo "Exiting workaround_bug905918" >> $OUTPUTFILE
}

function workaround_bug905910 ()
{
    # Bug 905910 - X.509: Cert # is not yet valid
    local ret=0
    OUTPUTFILE=`mktemp /tmp/tmp.XXXXXX`
    echo "Enter workaround_bug905910" >> $OUTPUTFILE
    if [ -f $OUTPUTDIR/boot.$kernbase ]; then
        grep -e "X.509: Cert [0-9a-fA-F]* is not yet valid" $OUTPUTDIR/boot.$kernbase > /dev/null
        if [ $? -eq 0 ]; then
            echo "Changing hwclock to UTC" | tee -a $OUTPUTFILE
            hwclock --systohc --utc >> $OUTPUTFILE 2>&1
            ret=$?
            cat /etc/adjtime | tee -a $OUTPUTFILE
            echo "Exiting workaround_bug905910" >> $OUTPUTFILE
            RprtRslt $TEST/set-hwclock WARN $ret
            if [ $ret -eq 0 ]; then
                rhts-reboot
            fi
        else
            echo "Kernel seems happy about Cert start date, not doing anything" | tee -a $OUTPUTFILE
        fi
    fi
    echo "Exiting workaround_bug905910" >> $OUTPUTFILE
}

function wait_for_kvm_setup ()
{
    # Bug 1473010 - [ALT][ppc64le] systems show different CPU count following kernel install
    # kernelinstall is racing with kvm-setup.service on ppc64le, which breaks cpu count check
    # we'll wait a bit here for kvm-setup service to start
    uname -m | grep ppc64le || return
    command -v systemctl || return
    [ "$(systemctl is-enabled kvm-setup)" == "enabled" ] || return

    echo "Waiting a bit for kvm-setup service to start" | tee -a $OUTPUTFILE
    i=0
    # shellcheck disable=SC2078
    while [ True ]; do
        systemctl status kvm-setup | grep "PID.*exited" && break
        i=$((i+1))
        sleep 2
        if [ $i -gt 60 ]; then
            echo "***** Giving up wait on kvm-setup service *****" | tee -a $OUTPUTFILE
            return
        fi
    done
    echo "kvm-setup should now be up" | tee -a $OUTPUTFILE
}

function CheckCPUcount ()
{
# BZ1050040
# This function checks to see if the CPU count value
# has changed between the base kernel and test kernel.
# If the  maxcpu  option is used on the
# kernel command line, then skip this check.

local maxcpuCheck=$(/bin/cat /proc/cmdline | grep -q maxcpu)$?
local system=$(/bin/uname -n)

DeBug "Enter CheckCPUcount"

wait_for_kvm_setup

# Skip CheckCPUcount for RHEL4 and all XEN kernels
if [[  "$testkernver" = "2.6.9" || "$KERNELARGVARIANT" = "xen" ]]; then
     DeBug " Skipping CheckCPUcount"
     echo "***** Skipping CheckCPUcount *****" >> $OUTPUTFILE
     DeBug "Exit CheckCPUcount"
     return 0
fi

# Check for use of kernel commandline  maxcpu  option
if [ "$maxcpuCheck" -gt "0" ]; then
    # The  maxcpu  option is not in use.
    # Lets check the CPU count.
    if [ "$RSTRNT_REBOOTCOUNT" -eq "0" ]; then
        # Lets get the CPU count for the base kernel.
        # We will save the base kernel variables, in order to survive a reboot.
        /bin/uname -r > /mnt/testarea/base_kernelSaved
        /bin/cat /proc/cpuinfo | /bin/grep ^processor | wc -l > /mnt/testarea/cpuCountSaved

        local base_kernel=$(/bin/cat /mnt/testarea/base_kernelSaved)
        local base_kernel_cpuCount=$(/bin/cat /mnt/testarea/cpuCountSaved)

        DeBug "  Check the system CPU count for kernel-${base_kernel}"
        echo "" >> $OUTPUTFILE
        echo "***** Check the system CPU count for kernel-${base_kernel} *****" >> $OUTPUTFILE
        echo "***** CPU count for kernel-${base_kernel} is: $base_kernel_cpuCount *****" >> $OUTPUTFILE
        echo "" >> $OUTPUTFILE

    else
        # A reboot was expected, as we are booting a new kernel for testing.
        # Lets get the CPU count for the test kernel.
        # Then lets compare the base kernel and test kernel values.
        local test_kernel=$(/bin/uname -r)
        local test_kernel_cpuCount=$(/bin/cat /proc/cpuinfo | /bin/grep ^processor | wc -l)
        # Lets restore the saved base_kernel variables
        local base_kernel=$(/bin/cat /mnt/testarea/base_kernelSaved)
        local base_kernel_cpuCount=$(/bin/cat /mnt/testarea/cpuCountSaved)

        DeBug "  Check and compare base_kernel_cpuCount and test_kernel_cpuCount values"
        echo "" >> $OUTPUTFILE
        echo "***** Comparing the CPU counts taken for the base kernel and test kernel *****" >> $OUTPUTFILE
        if [ "$base_kernel_cpuCount" -eq "$test_kernel_cpuCount" ]; then
            DeBug "  INFO: $system CPU count has not changed"
            echo "***** INFO: $system CPU count has not changed *****" >> $OUTPUTFILE
            echo "" >> $OUTPUTFILE
        else
            # Lets WARN the user, report the status, and continue testing.
            DeBug "  WARN: CPU count has changed"
            echo "***** kernel-${base_kernel} showed a CPU count of: $base_kernel_cpuCount *****" >> $OUTPUTFILE
            echo "***** kernel-${test_kernel} showed a CPU count of: $test_kernel_cpuCount *****" >> $OUTPUTFILE
            K_ReportStatus "Warn" "$system CPU count has changed" "CheckCPUcount"
            echo "" >> $OUTPUTFILE
        fi
    fi
else
    # The kernel command line contains the   maxcpu  option.
    # Display a notification and continue testing.
    DeBug "  INFO: /proc/cmdline has the  maxcpu  option"
    echo "" >> $OUTPUTFILE
    echo "***** INFO: /proc/cmdline has the  maxcpu  option *****" >> $OUTPUTFILE
    echo "" >> $OUTPUTFILE
fi

DeBug "Exit CheckCPUcount"
}

function Main ()
{
    DeBug "Enter Main"

    # Seed the log with an initial entry
    echo "***** Start of kernel install test *****" | tee -a $OUTPUTFILE

    # Make sure that /mnt/testarea/kernelinstall_kernel_to_boot does not exist
    rm -f /mnt/testarea/kernelinstall_kernel_to_boot

    # RHEL6-Beta repo workaround
    NukeRepo

    # Enable the Hypervisor and Console logging for xen tests
    XendLogging

    # CheckCPU count with base kernel
    CheckCPUcount

    if [ "$KERNELARGNAME" = "kernel-64k" ]; then
        CheckKernel $KERNELARGVERSION 64k-$KERNELARGVARIANT
    else
        CheckKernel $KERNELARGVERSION $KERNELARGVARIANT
    fi
    if [ "$?" = "1" ]; then
        # Check to see if the kernel we want to test is already installed
        rpm -qa --queryformat '%{name}-%{version}-%{release}.%{arch}\n' | grep -q $testkernbase.$kernarch
        if [ "$?" -ne "0" ]; then
            AddPermRepo
            AddTmpRepo
            # Workaround beaker ARCH env that causes %postinst of using system architecture name
            # instead of kernel architecture folder name
            BeakerARCH=$ARCH
            unset ARCH
            # Install kernel variant from yum repo
            YumInstallKernel
            if [ "$?" -ne "0" ]; then
                echo "***** Could not install from yum repo trying rpm -ivh from BREW *****" | tee -a $OUTPUTFILE
                # Install from yum failed lets try direct from brew
                BrewInstallKernel
                if [ "$?" -ne "0" ]; then
                    RprtRslt $TEST/BrewInstallkernel FAIL $?
                    DisableTmpRepo
                    RHTSAbort
                fi
            fi
            DisableTmpRepo
            ARCH=$BeakerARCH
        fi
        # Lets make it our default boot kernel the kernel we want to test
        SelectKernel $KERNELARGVERSION $KERNELARGVARIANT
        if [ "$?" -ne "0" ]; then
            RprtRslt $TEST/SelectKernel FAIL $?
        else
            # Now that the kernel is our default... Let's reboot
            echo "***** End of kernel install test *****" | tee -a $OUTPUTFILE
            if [ -f $OUTPUTDIR/boot.$kernbase ]; then
                SubmitLog $OUTPUTDIR/boot.$kernbase
            fi
            SubmitLog $DEBUGLOG
            RprtRslt $TEST/rhts-reboot PASS 0
            date --date="$(date --utc)" +%s > /mnt/testarea/kernelinstall_reboottime.log
            rhts-reboot
        fi
    else
        echo "***** The running kernel is the kernel we want to test *****" | tee -a $OUTPUTFILE
        echo "***** End of kernel install test *****" | tee -a $OUTPUTFILE
        if [ -f $OUTPUTDIR/boot.$kernbase ]; then
            SubmitLog $OUTPUTDIR/boot.$kernbase
        fi
        RprtRslt $TEST/$kernbase PASS $RSTRNT_REBOOTCOUNT
        DepmodChk
        SysReport
        [ -s "$DEBUGLOG" ] && SubmitLog "$DEBUGLOG"
        exit 0
    fi
    if [ "$KERNELARGVARIANT" == "xen" ]; then
        update_console
    fi
}

# strip trailing arch so it doesn't get accidentally doubled
KERNELARGVERSION=${KERNELARGVERSION%%.aarch64}
KERNELARGVERSION=${KERNELARGVERSION%%.ppc64le}
KERNELARGVERSION=${KERNELARGVERSION%%.s390x}
KERNELARGVERSION=${KERNELARGVERSION%%.x86_64}

# Record the test version in the debuglog
testver=$(rpm -qf $0)
DeBug "$testver"

# Current kernel variables
kernbase=$(rpm -q --queryformat '%{name}-%{version}-%{release}\n' -qf /boot/config-$(uname -r))
kernver=$(rpm -q --queryformat '%{version}\n' -qf /boot/config-$(uname -r))
kernrel=$(rpm -q --queryformat '%{release}\n' -qf /boot/config-$(uname -r))
kernarch=$(rpm -q --queryformat '%{arch}\n' -qf /boot/config-$(uname -r))
kernvariant=$(uname -r | awk -F $(uname -m) '{print $2}')
runkernel="${kernver}-${kernrel}${kernvariant#+}"

# drop -core- from name if present, this is to deal with meta-style
# packaging of kernel RPMs. Removing it here should be OK
# because kernbase is used only for naming of log/result files
kernbase=$(echo $kernbase | sed 's/-core-/-/')

DeBug "Running kernel variables"
DeBug "RUNNINGKERNEL=$runkernel"
DeBug "1=$kernbase 2=$kernver 3=$kernrel 4=$kernarch 5=$kernvariant"

# Test ARGS that are defined
DeBug "TEST ARGS (Environment variables)"
DeBug "1=$KERNELARGNAME 2=$KERNELARGVARIANT 3=$KERNELARGVERSION 4=$KERNELARGTMPREPO 5=$KERNELARGPERMREPO"

# Save KERNELARGNAME because it might be modified after this point in some
# cases, and will be necessary as a directory name to assemble the brewroot url
KERNPKGDIRECTORY="$KERNELARGNAME"

if [ "$KERNELARGNAME" = "kernel-64k" ]; then
    DeBug "substituting kernel-64k brew directory with kernel"
    KERNPKGDIRECTORY="kernel"
fi

# Pegas and aarch64 RPMs are named just 'kernel', work around any workflows
# that parse name out of (brew) package name and pass it here
if [ "$KERNELARGNAME" = "kernel-pegas" -o "$KERNELARGNAME" = "kernel-aarch64" ]; then
    DeBug "substituting $KERNELARGNAME with kernel in KERNELARGNAME"
    KERNELARGNAME="kernel"
fi

if [ "$KERNELARGNAME" = "kernel-alt" ]; then
    DeBug "substituting kernel-alt with kernel in KERNELARGNAME"
    KERNELARGNAME="kernel"
fi

# Handle RT kernels built from both a unified source tree and separate main-rt tree
RT_REQUESTED="false"
RT_DEBUG="false"
RT_UNIFIED="true"
if [[ "$KERNELARGVARIANT" = "rt"* || "$KERNELARGNAME" == "kernel-rt"* ]]; then
    RT_REQUESTED="true"
    KERNPKGDIRECTORY="kernel"
    if [[ "$KERNELARGVARIANT" = *"debug" || "$KERNELARGNAME" == *"debug" ]]; then
        # Handle if user requested KERNELARGVARIANT = debug, rt-debug, or rtdebug,
        # as well as if user requested KERNELARGNAME = kernel-rt-debug or kernel-rtdebug
        RT_DEBUG="true"
    fi
    if [[ "$KERNELARGVERSION" == *".rt"* ]]; then
        # Kernel RT built from the same source tree as kernel uses the same
        # NVR as kernel but will add "+rt" or "+rt-debug".  When built from
        # separate source trees however, kernel-rt has a unique NVR that
        # will include ".rtX.Y" version numbering instead, and does not append
        # "+rt" or "+rt-debug"
        RT_UNIFIED="false"
        KERNPKGDIRECTORY="kernel-rt"
    fi
    DeBug "RT Variables: RT_REQUESTED=$RT_REQUESTED RT_DEBUG=$RT_DEBUG RT_UNIFIED=$RT_UNIFIED KERNPKGDIRECTORY=$KERNPKGDIRECTORY"
fi

# New kernel variables
if [ "$KERNELARGVARIANT" == "up" ]; then
    DeBug "Running up variant, or newer smp"
    testkernbase=$KERNELARGNAME-$KERNELARGVERSION
    testkername=$KERNELARGNAME
    testkernver=$(echo $KERNELARGVERSION | awk -F- '{print $1}')
    testkernrel=$(echo $KERNELARGVERSION | awk -F- '{print $2}')
    testkerndevel=$KERNELARGNAME-devel-$KERNELARGVERSION
    testkerneluname=$KERNELARGVERSION
    DeBug "Test kernel variables"
    DeBug "1=$testkernbase 2=$testkername 3=$testkernver 4=$testkernrel 5=$testkerndevel"
else
    if [[ "$RT_REQUESTED" == "true" && "$RT_DEBUG" == "true" ]]; then
        # Ensure proper name "kernel-rt-debug" is handled regardless of what strings
        # the user utilized to request kernel-rt-debug
        testkernbase=kernel-rt-debug-$KERNELARGVERSION
        testkername=kernel-rt-debug
        testkerndevel=kernel-rt-debug-devel-$KERNELARGVERSION
    else
        testkernbase=$KERNELARGNAME-$KERNELARGVARIANT-$KERNELARGVERSION
        testkername=$KERNELARGNAME-$KERNELARGVARIANT
        testkerndevel=$KERNELARGNAME-$KERNELARGVARIANT-devel-$KERNELARGVERSION
    fi
    testkernver=$(echo $KERNELARGVERSION | awk -F- '{print $1}')
    testkernrel=$(echo $KERNELARGVERSION | awk -F- '{print $2}')
    testkernvariant=$KERNELARGVARIANT
    testkerneluname=$KERNELARGVERSION$KERNELARGVARIANT
    DeBug "Test kernel variables, in the else statement"
    DeBug "1=$testkernbase 2=$testkername 3=$testkernver 4=$testkernrel 5=$testkernvariant 6=$testkerndevel"
fi
testkernfirmware=kernel-firmware-$KERNELARGVERSION

# Determine if we are on RHEL5 distro
DeBug "Setting the default yum command"
yumcmd="yum"

DeBug "Setting the default CheckKernel Options"
OPTIONSCheckKernel="$KERNELARGVERSION $KERNELARGVARIANT"
if [ "$KERNELARGNAME" = "kernel-64k" ]; then
    OPTIONSCheckKernel="$KERNELARGVERSION 64k-$KERNELARGVARIANT"
fi

rpm -qf /etc/redhat-release | grep -q "redhat-release-5"
RHEL5TREE=$?
if [ "$RHEL5TREE" == "0" ] ; then
    DeBug "Running on RHEL5 Distribution"
    DeBug "Override yum command"
    yumcmd="yum --noplugins"
fi

cat /etc/redhat-release | grep -q "Santiago"
RHEL6TREE=$?
if [ "$RHEL6TREE" == "0" ] ; then
    DeBug "Running on RHEL6 Distribution"
    DeBug "Override yum command"
    yumcmd="yum --noplugins"
fi

# Generic test variables
if curl -s http://download-node-02.eng.bos.redhat.com/brewroot/packages/$KERNPKGDIRECTORY/$testkernver/$testkernrel/$kernarch/$testkernbase.$kernarch.rpm -o /dev/null -f; then
    httpbase=http://download-node-02.eng.bos.redhat.com/brewroot/packages/$KERNPKGDIRECTORY/$testkernver/$testkernrel
else
    httpbase=http://download-node-02.eng.bos.redhat.com/brewroot/vol/rhel-${RHEL_X}/packages/$KERNPKGDIRECTORY/$testkernver/$testkernrel
fi
archbase=http://download-node-02.eng.bos.redhat.com/brewroot/vol/kernelarchive/packages/$KERNPKGDIRECTORY/$testkernver/$testkernrel

if [ -z "$OUTPUTDIR" ]; then
    OUTPUTDIR=/mnt/testarea
fi

# Record lspci -xxx -vv
if [ -x /sbin/lspci ]; then
    /sbin/lspci -xxx -vv > $OUTPUTDIR/lspci.hexdump.$kernbase
    SubmitLog $OUTPUTDIR/lspci.hexdump.$kernbase
fi

# Record the boot messages
/bin/dmesg > $OUTPUTDIR/boot.$kernbase
if [ ! -s $OUTPUTDIR/boot.$kernbase ]; then
    # Workaround for /distribution/install zeroing out the dmesg file
    cp $OUTPUTDIR/boot.messages $OUTPUTDIR/boot.$kernbase
fi

if [ "${RSTRNT_REBOOTCOUNT}xx" == "xx" ]; then
    RSTRNT_REBOOTCOUNT=0
fi

if [ -z "$KERNELARGNAME" -o -z "$KERNELARGVARIANT" -o -z "$KERNELARGVERSION" ]; then
    echo "***** Test argument(s) are empty! Can't continue. *****" | tee -a $OUTPUTFILE
    DeBug "name=$KERNELARGNAME variant=$KERNELARGVARIANT version=$KERNELARGVERSION"
    RprtRslt $TEST/$kernbase FAIL 1
    exit 0
else
    if [ "$RSTRNT_REBOOTCOUNT" == "0" ]; then
        Main
    elif [ "$RSTRNT_REBOOTCOUNT" == "1" ]; then
        if [ -f $OUTPUTDIR/boot.$kernbase ]; then
            SubmitLog $OUTPUTDIR/boot.$kernbase
        fi
        DeBug "Running CheckKernel $OPTIONSCheckKernel"
        CheckKernel $OPTIONSCheckKernel
        if [ "$?" = "1" ]; then
            DeBug "After reboot we are still not running the correct kernel"
            RprtRslt $TEST/$kernbase FAIL $RSTRNT_REBOOTCOUNT
            RHTSAbort
        else
            DeBug "After reboot we are running the correct kernel"
            # CheckCPU count with test kernel
            CheckCPUcount
            YumUpgradeKernelHeaders
            REBOOT_TIME=$(cat /mnt/testarea/kernelinstall_reboottime.log)
            DIFF=$(expr ${CUR_TIME} - ${REBOOT_TIME})
            if [[ ${DIFF} -gt ${MAX_REBOOT_TIME:-480} ]]; then
                 let DIFF_MIN=$DIFF/60
                 let DIFF_SEC=$DIFF%60
                 echo "***** WARN: rhts-reboot took ${DIFF_MIN} minutes and ${DIFF_SEC} second(s), that exceeded ${MAX_REBOOT_TIME:-480} seconds *****" | tee -a $OUTPUTFILE
                 RprtRslt $TEST/${kernbase}_boot WARN $DIFF
            fi
            RprtRslt $TEST/$kernbase PASS $DIFF
            DepmodChk
            DiffDmesg
            if [ -x /sbin/lspci ]; then
                DiffLspci
            fi
            SysReport
        fi
        SubmitLog $DEBUGLOG
        workaround_bug905910
    else
        if [ -f $OUTPUTDIR/boot.$kernbase ]; then
            SubmitLog $OUTPUTDIR/boot.$kernbase
        fi
        RprtRslt $TEST/boot PASS 0
    fi
fi
