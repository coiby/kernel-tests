function test_min_free_kbytes(){
    sub=`expr $cal_min_free_kbyte - $min_free_kbytes`
    if [[ "$arch" == "ppc64le" ]]; then
    #The error in ppc64le will be larger during testing.
        pos=`expr $min_free_kbytes / 30`
        if((sub > pos || sub < (($pos * -1)))); then
            rlLogInfo "min_free_kbytes is $min_free_kbytes, but the value that we calculate is $cal_min_free_kbyte (the memory is $mem K)"
            rlReport "bz1808039" FAIL
        else
            rlLogInfo "min_free_kbytes is $min_free_kbytes(the value that we calculate is $cal_min_free_kbyte and the memory is $mem K)"
        fi
    else
        if((sub > 200 || sub < -200)); then
        #200k is an experiential value during testing 
            rlLogInfo "min_free_kbytes is $min_free_kbytes, but the value that we calculate is $cal_min_free_kbyte (the memory is $mem K)"
            rlReport "bz1808039" FAIL
        else
            rlLogInfo "min_free_kbytes is $min_free_kbytes(the value that we calculate is $cal_min_free_kbyte and the memory is $mem K)"
        fi
    fi
}
function bz1808039()
{
    local min_free_kbytes
    local cal_min_free_kbyte
    local temp
    local sub
    local pos
    local ver
    local ker
    local val
    local arch=$(uname -m)
    local mem=$(cat /proc/meminfo | grep MemTotal | awk '{print$2}')
    local rebootflag_f=${DIR_DEBUG}/REBOOT_${FUNCNAME}_F
    local rebootflag_s=${DIR_DEBUG}/REBOOT_${FUNCNAME}_S
    cat /proc/cmdline | grep transparent_hugepage=never
    temp=$?
    
    if [ -f "$rebootflag_s" ]; then
        return 0;
    fi
    if [ ! -f "$rebootflag_f" ]; then
        if((temp != 0)); then
            if [[ "$arch" == "s390x" ]]; then
                rlRun "grubby --update-kernel=ALL --args="transparent_hugepage=never"" 0
                rlRun "zipl" 0
                rlLogInfo "$FUNCNAME: reboot the machine to disable transparent_hugepage"
                touch $rebootflag_f
                rhts-reboot
            else 
                rlRun "grubby --update-kernel=ALL --args="transparent_hugepage=never"" 0 
                rlRun "grubby --info=ALL" 0
                rlLogInfo "$FUNCNAME: reboot the machine to disable transparent_hugepage"
                touch $rebootflag_f
                rhts-reboot
            fi
        fi
    else
        rlLogInfo "transparent hugepage should be disable"
        min_free_kbytes=$(cat /proc/sys/vm/min_free_kbytes)
        yum -y install bc
        cal_min_free_kbyte=$(echo "sqrt($mem * 16)" | bc)
        if((mem <= 1024)); then
            rlAssertEquals "min_free_kbytes should be 128 (<1M)" "$min_free_kbytes" "128"
        elif((mem >= 268435456 && mem < 4294967296)); then
            if rlIsRHEL "<8"; then
                test_min_free_kbytes
            else
                if rlIsRHEL "<9"; then
                    ver=$(uname -r | grep -Eo '\-[0-9]*.')
                    ker=${ver:1:len-1}
                    if((ker < 193)); then
                        rlAssertEquals "min_free_kbytes should be 65536 (>256G)" "$min_free_kbytes" "65536"
                    elif((ker == 193)); then
                        ver=$(uname -r | grep -Eo '\-[0-9]*.[0-9]*')
                        val=`echo $ver | tr -cd "[0-9]"`
                        if(((val > 1938) || (val == 193))); then
                            test_min_free_kbytes
                        else
                            rlAssertEquals "min_free_kbytes should be 65536 (>256G)" "$min_free_kbytes" "65536"
                        fi
                    else
                        test_min_free_kbytes
                    fi
                else
                    test_min_free_kbytes
                fi
            fi
        elif((mem >= 4294967296)); then
            if rlIsRHEL "<8"; then
                rlAssertEquals "min_free_kbytes should be 262144 (>4T)" "$min_free_kbytes" "262144"
            else
                if rlIsRHEL "<8.3"; then
                    rlAssertEquals "min_free_kbytes should be 65536 (>4T)" "$min_free_kbytes" "65536"
                elif rlIsRHEL "<9"; then
                    ver=$(uname -r | grep -Eo '\-[0-9]*.')
                    ker=${ver:1:len-1}
                    if((ker < 193)); then
                        rlAssertEquals "min_free_kbytes should be 65536 (>4T)" "$min_free_kbytes" "65536"
                    elif((ker == 193)); then
                        ver=$(uname -r | grep -Eo '\-[0-9]*.[0-9]*')
                        val=`echo $ver | tr -cd "[0-9]"`
                        if(((val > 1938) || (val == 193))); then
                            rlAssertEquals "min_free_kbytes should be 262144 (>4T)" "$min_free_kbytes" "262144"
                        else
                            rlAssertEquals "min_free_kbytes should be 65536 (>4T)" "$min_free_kbytes" "65536"
                        fi
                    else
                        rlAssertEquals "min_free_kbytes should be 262144 (>4T)" "$min_free_kbytes" "262144"
                    fi
                else
                    rlAssertEquals "min_free_kbytes should be 262144 (>4T)" "$min_free_kbytes" "262144"
                fi
            fi
        else
            test_min_free_kbytes    
        fi
        if [[ "$arch" == "s390x" ]]; then
            rlRun "grubby --remove-args="transparent_hugepage=never" --update-kernel=ALL" 0
            rlRun "zipl" 0
        else
            rlRun "grubby --remove-args="transparent_hugepage=never" --update-kernel=ALL" 0
            rlRun "grubby --info=ALL" 0
        fi
        rlLogInfo "$FUNCNAME: reboot the machine to original"
    	rlRun "touch $rebootflag_s"
        rhts-reboot
        cat /proc/cmdline | grep transparent_hugepage=never
        temp=$?
        if((temp == 0)); then
            rlReport "bz1808039" WARN
        fi
    fi
}
