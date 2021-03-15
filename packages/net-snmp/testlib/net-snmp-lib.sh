#!/bin/bash
# Copyright (c) 2010 Red Hat, Inc. All rights reserved. This copyrighted material.
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
# Author: Jan Safranek

. /usr/bin/rhts-environment.sh
. /usr/lib/beakerlib/beakerlib.sh


# returns the snmpd sysconfig file location
function get_sysconfig_path() {
    # snmpd.sysconfig
    # find where it belongs - different versions have different places
    SYSCONFIG_NAME=""
    SCRIPT=/etc/init.d/snmpd
    [ -f /usr/lib/systemd/system/snmpd.service ] && SCRIPT=/usr/lib/systemd/system/snmpd.service
    for candidate in "/etc/sysconfig/snmpd" "/etc/sysconfig/snmpd.options" \
            "/etc/snmp/snmpd.options"; do
        if grep -qw "$candidate" $SCRIPT; then
            SYSCONFIG_NAME=$candidate
        fi
    done
    if [ -e /lib/systemd/system/snmpd.service ]; then
        SYSCONFIG_NAME="/etc/sysconfig/snmpd"
    fi
    echo $SYSCONFIG_NAME
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsInstallConfig
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Install configuration files.

=head3 nsInstallConfig

Install configuration files from current directory to C</etc/snmp/>. Backs up
the old ones before rewriting. Creates appropriate SELinux context of these
files.

Recognized files are C<snmpd.conf>, C<snmpd.sysconfig>, C<snmp.conf> and
C<snmptrapd.conf>.

When no C<snmpd.conf>, C<snmpd.sysconfig> and/or C<snmp.conf> are provided,
default ones are created (with C<rwcommunity public> and default logging to
/var/log/snmpd.log).

=cut
nsInstallConfig() {
    rlFileBackup --namespace net-snmp-lib --clean /etc/snmp /var/lib/net-snmp
    # snmpd.conf
    if [ -e snmpd.conf ]; then
        rlRun "cp snmpd.conf /etc/snmp/snmpd.conf" || return 1
    else
        echo "rwcommunity public" >/etc/snmp/snmpd.conf
    fi
    rlRun "restorecon /etc/snmp/snmpd.conf" || return 1

    # snmpd.sysconfig
    # find where it belongs - different versions have different places
    SYSCONFIG_NAME=`get_sysconfig_path`
    if [ -z "$SYSCONFIG_NAME" ]; then
        rlAssert0 "Cannot find name of sysconfig file!" 1
        return 1
    fi
    rlFileBackup --namespace net-snmp-lib --clean $SYSCONFIG_NAME
    # finally create snmpd.sysconfig
    if [ -e snmpd.sysconfig ]; then
        rlRun "cp snmpd.sysconfig $SYSCONFIG_NAME"
    else
        # create default content - in rhel <= 5 log everything, on rhel6 log 0-6
        #if [ `rlGetDistroRelease` -ge 6 ]; then
        if ! rlIsRHEL 3 4 5; then   # this is a workaround because of bug 587626
            echo "OPTIONS='-p /var/run/snmpd.pid -LF 0-6 /var/log/snmpd.log'" >"$SYSCONFIG_NAME"
        else
            echo "OPTIONS='-p /var/run/snmpd.pid -Lf /var/log/snmpd.log'" >"$SYSCONFIG_NAME"
        fi
    fi
    rlRun "restorecon $SYSCONFIG_NAME"

    # snmp.conf
    if [ -e snmp.conf ]; then
        rlRun "cp snmp.conf /etc/snmp/snmp.conf" || return 1
    else
        printf "defVersion 2c\ndefCommunity public\n" >/etc/snmp/snmp.conf
    fi
    rlRun "restorecon /etc/snmp/snmp.conf" || return 1

    # snmptrapd.conf
    if [ -e snmptrapd.conf ]; then
        rlRun "cp snmptrapd.conf /etc/snmp/snmptrapd.conf" || return 1
        rlRun "restorecon /etc/snmp/snmptrapd.conf" || return 1
    fi

    # /var/net-snmp/snmp.conf
    for i in /var/lib/net-snmp /var/net-snmp ; do
        if [ -d $i ]; then
            restorecon -R $i
        fi
    done

    rlLog "=== snmpd.conf ===:"
    rlLog "`cat /etc/snmp/snmpd.conf`"
    rlLog "=== snmp.conf ===:"
    rlLog "`cat /etc/snmp/snmp.conf`"
    rlLog "=== $SYSCONFIG_NAME ===:"
    rlLog "`cat $SYSCONFIG_NAME`"
    if [ -e snmptrapd.conf ]; then
        rlLog "=== snmptrapd.conf ===:"
	rlLog "`cat /etc/snmp/snmptrapd.conf`"
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsPrepareService
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Prepare server

=head3 nsPrepareService

Prepares everything to start a server. This should be the only preparation
needed when you don't need to start snmpd daemon in any special way, just with
the right config file.

=item * Install configuration files using C<nsInstallConfig>.

=cut
nsPrepareService() {
    nsInstallConfig

    killall snmpd snmptrapd 2>/dev/null
    rm /var/log/snmpd.log 2>/dev/null
    rlLog "nsPrepareService done"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsCleanup
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Clean up test

=head3 nsCleanup

Restore backup files and check snmpd.log for suspicios messages. This is
supposed to be started in Cleanup test phase.

=item * Checks snmpd log file using C<nsCheckLog>.

=cut

nsCleanup() {
    rlRun "pidof snmpd snmptrapd" 1 "Check that snmpd and snmptrapd is not running"
    killall -9 snmpd snmptrapd 2>/dev/null
    rlFileRestore --namespace net-snmp-lib
    rlRun "nsCheckLog"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsCheckAndStop
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Check if service is running and stop it

=head3 nsCheckAndStop <service>

Check if servcice is running and return error if not. Then stop the service.

=cut

nsCheckAndStop() {
    if which systemctl &>/dev/null; then
        systemctl status $1
    else
        service $1 status
    fi
    RET=$?
    if which systemctl &>/dev/null; then
        systemctl stop $1
    else
        service $1 stop
    fi
    RET2=$?
    if [ "$RET2" -ne "0" ]; then
        RET=$RET2
    fi
    return $RET
}
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsCheckLog
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Check log file for unusual messages.

=head3 nsCheckLog [filename]

/var/log/snmpd.log is take if C<filename> is not specified. Caller might set
C<$IGNORE_LOGS> for additional messages to ignore (i.e. considered valid). The
C<$IGNORE_LOGS> must be regular expression and must start with C<|> character.

=cut

nsCheckLog() {
    LOGFILE=$1
    if [ -z "$LOGFILE" ]; then
        LOGFILE=/var/log/snmpd.log
    fi
    if [ ! -e "$LOGFILE" ]; then
        rlLog "No logfile found"
        return 0;
    fi
    SNMPD_EXTRA=`mktemp`
    rlRun "egrep -v '(^\$|NET-SNMP version|Connection from ...|Received SNMP packet|\[init_smux\] bind failed: Permission denied|Creating directory: /var/agentx|read_config_store open failure on /var/net-snmp/snmpd.conf|Received TERM or STOP signal...  shutting down...|Creating directory: /var/net-snmp|mibII/mta_sendmail.c:open_sendmailst|_ifXTable_container_row_restore|Created directory: /var/lib/net-snmp/mib_indexes|Created directory: /var/lib/net-snmp/mib_indexes|Created directory: /var/lib/net-snmp/cert_indexes|Duplicate IPv4 address detected, some interfaces may not be visible in IP-MIB|$IGNORE_LOGS)' $LOGFILE >$SNMPD_EXTRA" \
        1 "Checking the log file for unknown entries"
    if [ "$?" -ne "1" ]; then
        rlLog "Suspicious messages in the snmpd.log:"
        rlLog "`cat $SNMPD_EXTRA`"
    fi
    rm $SNMPD_EXTRA
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsTagBin
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Create executable selinux context.

=head3 nsTagBin <filename>

Change the selinux context of C<filename> to allow snmpd/snmptrapd to execute
it.

=cut
nsTagBin() {
    chcon --reference=/bin/cp $1
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsTagWrite
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Create writable selinux directory context

=head3 nsTagWrite <dir>

Change the SELinux context of directory C<dir> to allow snmpd/snmptrapd to write
to it.

=cut
nsTagWrite() {
    local WDIR=$1
    chcon --reference=/var $WDIR
    [ -e /var/net-snmp/ ] && ( chcon --reference=/var/net-snmp $WDIR || return 1 )
    [ -e /var/lib/net-snmp/ ] && ( chcon --reference=/var/lib/net-snmp $WDIR \
        || return 1 )
    return 0
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsChrootPrepare
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Prepare chroot environment

=head3 nsChrootPrepare <dir>

Creates filesystem structure on C<dir> to be able to start chrooted snmpd there.
Everything except /proc is real there. In /proc, few processes and most of
the stats are there. In general, snmpd should work, it sometimes just complains
in log.

=cut
nsChrootPrepare() {
    local ROOT=$1
    local dir f
    rlLog "Preparing chroot $ROOT"
    # just bind all directories in / except /proc
    for dir in `ls -d /[^pt]*`; do
        if [ -d $dir ]; then
            mkdir $ROOT/$dir || return 1
            mount --bind $dir $ROOT/$dir || return 1
        fi
    done
    mkdir $ROOT/proc || return 1
    mkdir $ROOT/tmp || return 1
    # copy few processes (0-9) and the files we're interested in to /proc
    cp /proc/[^k]* $ROOT/proc 2>/dev/null
    local files=$(find /proc/[0-9] /proc/vmstat /proc/net/ /proc/sys /proc/cpu* /proc/*stat* -type f ! -name pagemap ! -name use-gss-proxy 2>/dev/null | egrep -v "/task|/fd")
    for f in $files; do
        #echo Preparing to copy $f
        d=$(dirname $f)
        mkdir -vp $ROOT/$d &>/dev/null
        cp $f $ROOT/$f  &>/dev/null
    done
    cat /proc/net/dev >$ROOT/proc/net/dev || return 1
    chcon -R --reference=/proc $ROOT/proc
    return 0
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsChrootCleanup
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Clean chroot environment

=head3 nsChrootCleanup <dir>

Removes/unmounts everything what was created by C<nsChrootPrepare> from the
C<dir>.

=cut
nsChrootCleanup() {
    local ROOT=$1 dir

    rlLog "Removing chroot $ROOT"
    for dir in `ls -d /[^pt]*`; do
        umount $ROOT/$dir &>/dev/null
        rmdir $ROOT/$dir &>/dev/null
    done
    rm -rf $ROOT/proc &>/dev/null
    rm -rf $ROOT/tmp &>/dev/null
    return 0
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsChrootStartService
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Start snmpd in chroot.

=head3 nsChrootStartService <dir>

Start snmpd daemon in chroot in C<dir>.

=cut
nsChrootStartService() {
    local ROOT=$1
    #rlRun "chroot $ROOT /sbin/service snmpd start"
    # on rhel7 we cannot start snmpd using /sbin/service in chroot anymore
    # we need to execute it manually and use ugly hack to run snmpd with correct selinux context
    cat > /bin/snmpd_starter <<"EOF"
#!/bin/bash
`which snmpd` $@
EOF
    chmod a+x /bin/snmpd_starter
    chcon -u system_u -r object_r -t initrc_exec_t /bin/snmpd_starter
    #rlRun "chroot $ROOT /sbin/service snmpd start"
    . `get_sysconfig_path`
    rlRun "runcon -u system_u -r system_r -t initrc_t chroot $ROOT /bin/snmpd_starter $OPTIONS"
    sleep 3
    ps -eZ | grep snmpd
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nsChrootStopService
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<=cut
=pod

=head2 Stop snmpd in chroot.

=head3 nsChrootStopService <dir>

Stops snmpd daemon in chroot in C<dir>.

=cut
nsChrootStopService() {
    local ROOT=$1
    #rlRun "nsCheckAndStop snmpd"
    kill `pidof snmpd`
    sleep 5
    pidof snmpd && kill -9 `pidof snmpd`
    rm -f /bin/snmpd_starter
    return 0
}

