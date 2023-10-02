#!/bin/sh

# Source the common test script helpers
. ../../kernel-include/runtest.sh

# PARAMS: KPATCHNVR, KERNELREPOTMPL, KPATCHURL

KPATCHNVR=${KPATCHNVR:-}
KPATCHURL=${KPATCHURL:-}

function logmsg ()
{
    echo "* kpatchinstall $(date):  $1" | tee -a $OUTPUTFILE
}

function RHTSAbort ()
{
    logmsg "Aborting recipe: $1"
    rhts-abort -t recipe
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
}

function install_kpatch_yum ()
{
    logmsg "install_kpatch_yum start"

    $yumcmd -y install $KPATCHNVR >> $OUTPUTFILE 2>&1
    local ret=$?
    if [ "$ret" -ne "0" ]; then
        logmsg "Yum returned an error while trying to install $KPATCHNVR, err: $ret"
        logmsg "Exit install_kpatch_yum FAIL 3 (YUM exited with a failure)"
        return 3
    else
        logmsg "Check to see if kpatch is now installed, using yum"
        $yumcmd list installed $KPATCHNVR | grep -q installed
        ret=$?
        if [ "$ret" -ne "0" ]; then
            logmsg "Double check, this time using rpm"
            rpm -qa --queryformat '%{name}-%{version}-%{release}.%{arch}\n' | grep -q $KPATCHNVR
            ret=$?
            if [ "$ret" -ne "0" ]; then
                logmsg "Failed to find $KPATCHNVR in installed"
                logmsg "Exit install_kpatch_yum FAIL 4 (Thought we installed but can't find it)"
                return 4
            fi
        fi
    fi
    logmsg "install_kpatch_yum end"
}

[ -z "$KPATCHNVR" ] && [ -z "$KPATCHURL" ] && \
    RHTSAbort "Either KPATCHNVR or KPATCHURL should be provided"

[ ! -z "$KPATCHURL" ] && \
    KPATCHNVR=$(echo ${KPATCHURL##*/} | sed -e "s/.rpm//"  -e "s/.$(uname -m)//")

kpatch_name=$(echo $KPATCHNVR | cut -d- -f1,2,3,4)
kpatch_version=$(echo $KPATCHNVR | cut -d- -f5)
kpatch_release=$(echo $KPATCHNVR | cut -d- -f6)

[ -z "$KPATCHURL" ] && \
    KPATCHURL="http://download.devel.redhat.com/brewroot/packages/${kpatch_name}/${kpatch_version}/${kpatch_release}/$(uname -m)/${KPATCHNVR}.$(uname -m).rpm"

function install_kpatch_brew ()
{
    logmsg "install_kpatch_brew start"

    yum install -y "$KPATCHURL" > .tmp 2>&1
    local ret=$?
    cat .tmp | tee -a $OUTPUTFILE
    rm -f .tmp
    if [ $ret -ne 0 ]; then
        logmsg "Failed to brew_install $KPATCHNVR rpm"
        RprtRslt $TEST/install_kpatch_brew FAIL $ret
        RHTSAbort "Failed to brew_install $KPATCHNVR rpm"
    fi

    logmsg "Check to see if kpatch is now installed, using rpm"
    rpm -qa --queryformat '%{name}-%{version}-%{release}.%{arch}\n' | grep -q $KPATCHNVR
    if [ "$ret" -ne "0" ]; then
        logmsg "Failed to find $KPATCHNVR in rpm nstalled"
        logmsg "Exit install_kpatch_rpm FAIL 5 (Thought we installed but can't find it)"
        return 5
    fi

    logmsg "install_kpatch_brew end"

    return $ret
}

function download_kpatch_brew ()
{
    logmsg "download_kpatch_brew start"

    curl -L "$KPATCHURL" -O > .tmp 2>&1
    local ret=$?
    cat .tmp | tee -a $OUTPUTFILE
    rm -f .tmp
    if [ $ret -ne 0 ]; then
        logmsg "Failed to download $KPATCHNVR rpm"
        RprtRslt $TEST/download_kpatch_rpm_brew FAIL $ret
        RHTSAbort "Failed to download $KPATCHNVR rpm"
    fi
    local kpatch_rpm=$(ls $KPATCHNVR.* | tail -1)
    if [ ! -e $kpatch_rpm ]; then
        logmsg "Failed to find kpatch $KPATCHNVR rpm"
        ls -la >> $OUTPUTFILE 2>&1
        RprtRslt $TEST/download_kpatch_rpm_brew FAIL 1
        RHTSAbort "Failed to find kpatch $KPATCHNVR rpm"
    fi

    logmsg "download_kpatch_brew end"

    return $ret
}

function download_kpatch_rpm ()
{
    logmsg "download_kpatch_rpm start"
    if [ -z "$KPATCHNVR" ]; then
        RHTSAbort "KPATCHNVR parameter is empty"
    fi

    # remove old stuff
    rm -f $KPATCHNVR.*.rpm

    # download RPM
    yumdownloader -v "$KPATCHNVR" > .tmp 2>&1
    local ret=$?
    cat .tmp | tee -a $OUTPUTFILE
    rm -f .tmp
    if [ $ret -ne 0 ]; then
        logmsg "Failed to download $KPATCHNVR rpm from yum repo, trying to curl from BREW"
        download_kpatch_brew
        ret=$?
        if [ "$ret" -ne "0" ]; then
            RprtRslt $TEST/brew_download_kpatch FAIL $ret
            RHTSAbort "Could not download from yum repo or brew"
        fi
    fi

    local kpatch_rpm=$(ls $KPATCHNVR.* | tail -1)
    if [ ! -e $kpatch_rpm ]; then
        logmsg "Failed to find kpatch $KPATCHNVR rpm"
        ls -la >> $OUTPUTFILE 2>&1
        RprtRslt $TEST/download_kpatch_rpm FAIL 1
        RHTSAbort "Failed to find kpatch $KPATCHNVR rpm"
    fi
    logmsg "download_kpatch_rpm end"
}

function install_kpatch ()
{
    logmsg "install_kpatch start"
    install_kpatch_yum
    local ret=$?
    if [ "$ret" -ne "0" ]; then
        logmsg "Could not install from yum repo trying rpm -ivh from BREW"
        install_kpatch_brew
        ret=$?
        if [ "$ret" -ne "0" ]; then
            RprtRslt $TEST/brew_install_kpatch FAIL $ret
            RHTSAbort "Could not install from yum repo or brew"
        fi
    fi
    lsmod | grep kpatch | tee -a $OUTPUTFILE
    logmsg "install_kpatch end"
}

function prepare_for_kernelinstall ()
{
    local py_cmd="python"
    rhel_version=$(cut -f 1 -d "." /etc/redhat-release | sed -e 's/[^0-9]//g')
    [ "$rhel_version" == "8" ] && py_cmd="/usr/libexec/platform-python"

    logmsg "prepare_for_kernelinstall start"

    if [ -z "$KERNELARGNAME" ]; then
        KERNELARGNAME="kernel"
    fi
    if [ -z "$KERNELARGVARIANT" ]; then
        KERNELARGVARIANT="up"
    fi

    if [ -z "$KERNELARGVERSION" ]; then
        local kpatch_rpm=$(ls $KPATCHNVR.* | tail -1)

        logmsg "Looking for latest supported kernel in RPM: $kpatch_rpm"
        rpm -qpl $kpatch_rpm | tee -a $OUTPUTFILE 2>&1

        local latest_kernel_vr=$(rpm -qpl $kpatch_rpm | grep \.ko | grep -v kpatch\.ko | $py_cmd find_latest_vr.py)
        logmsg "Latest supported kpatch module vr is $latest_kernel_vr"

        # strip arch
        local latest_kernel_vr=$(echo $latest_kernel_vr | sed 's/\(.[^.]*\)$//')
        logmsg "Latest kernel version-release: $latest_kernel_vr"

        KERNELARGVERSION="$latest_kernel_vr"
    fi

    local latest_kernel_version=$(echo $KERNELARGVERSION | sed 's/\(-[^-]\+\)$//')
    local latest_kernel_release=$(echo $KERNELARGVERSION | sed 's/.*-\([^-]\+\)$/\1/')
    logmsg "latest_kernel_version: $latest_kernel_version, latest_kernel_release: $latest_kernel_release"

    if [ -z "$KERNELARGVERSION" ]; then
        logmsg "KERNELARGVERSION is empty, failed to find latest supported kernel"
        RHTSAbort
    fi

    if [ -n "$KERNELREPOTMPL" ]; then
        # example: http://${baseurl}/repos/#name/#version/#release
        local repourl=$KERNELREPOTMPL
        logmsg "kernel repourl: $repourl ->"
        repourl=$(echo $repourl | sed "s/#name/kernel/")
        logmsg "kernel repourl: $repourl ->"
        repourl=$(echo $repourl | sed "s/#version/$latest_kernel_version/")
        logmsg "kernel repourl: $repourl ->"
        repourl=$(echo $repourl | sed "s/#release/$latest_kernel_release/")
        logmsg "kernel repourl: $repourl"

        cat << EOF >/etc/yum.repos.d/kpatchinstall-kernel.repo
[kpatchinstall-kernel]
name=kpatchinstall-kernel
baseurl=$repourl
enabled=1
gpgcheck=0
skip_if_unavailable=1
EOF

        cat /etc/yum.repos.d/kpatchinstall-kernel.repo | tee -a $OUTPUTFILE
        echo >> $OUTPUTFILE
    fi

    export KERNELARGNAME
    export KERNELARGVERSION
    export KERNELARGVARIANT

    logmsg "prepare_for_kernelinstall end"
}

function run_kernelinstall ()
{
    logmsg "run_kernelinstall start"
    if [ -e "../kernelinstall" ]; then
        cd ../kernelinstall
    else
        RHTSAbort "Unable to find kernelinstall directory"
    fi

    logmsg "KERNELARGNAME=$KERNELARGNAME, KERNELARGVERSION=$KERNELARGVERSION, KERNELARGVARIANT=$KERNELARGVARIANT"
    logmsg "run_kernelinstall about to start kernelinstall test.."
    if [ "$REBOOTCOUNT" -eq "0" ]; then
        RprtRslt "kernelinstall/start" PASS 0
        echo > $OUTPUTFILE
    fi
    rhts-flush
    chmod a+x runtest.sh ; ./runtest.sh
    echo > $OUTPUTFILE
    logmsg "run_kernelinstall end"
    RprtRslt "kernelinstall/done" PASS 0
}

function verify_kpatch_loaded ()
{
    logmsg "verify_kpatch_loaded start"
    ls -1 /usr/lib/kpatch/$(uname -r) | grep -v kpatch\.ko | sed 's/\.ko//' | tr - _ | tr . _ > mod_names
    logmsg "Installed kpatch mod names"
    cat mod_names | tee -a $OUTPUTFILE

    logmsg "Loaded kpatch modules"
    lsmod | grep -f mod_names >> $OUTPUTFILE
    if [ $? -eq 0 ]; then
        RprtRslt "done" PASS 0
    else
        RprtRslt "done" FAIL 1
        RHTSAbort "Failed to verify that kpatch module loaded"
    fi
    rm -f mod_names
    logmsg "verify_kpatch_loaded end"
    return 0
}

# init variables, if this is run by hand
if [ -z "$REBOOTCOUNT" ]; then
    REBOOTCOUNT=0
fi
if [ -z "$OUTPUTFILE" ]; then
    OUTPUTFILE="/mnt/testarea/TESTOUT.log"
fi
yumcmd="yum"

logmsg "REBOOTCOUNT: $REBOOTCOUNT, KERNELARGVERSION: $KERNELARGVERSION, KPATCHNVR: $KPATCHNVR"
# download kpatch rpm
if [ "$REBOOTCOUNT" -eq "0" ]; then
    rm -rf .running_desired_kernel
    download_kpatch_rpm
fi

# install kernel
prepare_for_kernelinstall
if [ ! -e .running_desired_kernel ]; then
    run_kernelinstall
fi

# when run_kernelinstall returns we can be sure we are running desired kernel
touch .running_desired_kernel

# install and verify kpatch rpm
install_kpatch
verify_kpatch_loaded

exit 0
