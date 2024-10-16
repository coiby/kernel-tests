#!/bin/sh
set -xe

if [ -f /usr/lib/systemd/system/restraintd.service ]; then
    if grep -qE "^OOMPolicy=continue$" /usr/lib/systemd/system/restraintd.service; then
        echo "restraintd already contains OMPolicy=continue"
    else
        # Patch restraintd service to continue after OOM, some tests generate OOM and restraintd should continue to run
        sed -i '/OOMScoreAdjust=.*/a OOMPolicy=continue' /usr/lib/systemd/system/restraintd.service
    fi
fi

mkdir -p /usr/share/rhts/

# Silence dmesg warnings for known issues
cat >/usr/share/rhts/falsestrings <<EOF
BIOS BUG
DEBUG
mapping multiple BARs.*IBM System X3250 M4
MAX_LOCKDEP_CHAIN_HLOCKS
BUG: KASAN: use-after-free in string_nocheck
watchdog: BUG: soft lockup - CPU
EOF
echo "/usr/share/rhts/falsestrings is"
cat /usr/share/rhts/falsestrings

# workaround for https://github.com/restraint-harness/restraint/issues/273
cat >/usr/share/rhts/failurestrings <<EOF
\bOops\b
\bBUG\b
NMI appears to be stuck
Badness at
EOF
echo "/usr/share/rhts/failurestrings is"
cat /usr/share/rhts/failurestrings

# Patch restraint's localwatchdog plugin to abort the recipe instead of warning,
# when a task goes over KILLTIMEOVERRIDE.
# The ABORT task result isn't accepted as a valid result, we should instead change it to:
# 'sed -i 's|rstrnt-reboot|rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status\nrstrnt-reboot|' /usr/share/restraint/plugins/localwatchdog.d/99_reboot'
# Otherwise you may see "Failed to submit result, status: 400 Message: BAD REQUEST"
# see: https://bugzilla.redhat.com/show_bug.cgi?id=1716997
# also if the task has ABORT_RECIPE_ON_LWD parameter set to 1 it will abort the whole recipe (For example, a boot test task should abort the whole recipe if hits lwd)
# shellcheck disable=SC2016 # we don't want to expand the variable when writing to the file
sed -i 's|rstrnt-reboot|if [ "${CKI_ABORT_RECIPE_ON_LWD:-0}" -eq "1" ]; then rstrnt-abort recipe; else rstrnt-report-result "${RSTRNT_TASKNAME}" WARN\nexit 0\nrstrnt-reboot;fi|' /usr/share/restraint/plugins/localwatchdog.d/99_reboot

# Show information the test aborted due to localwatchdog
# shellcheck disable=SC2016 # we don't want to expand the variable when writing to the file
if ! grep -q "\${RSTRNT_TASKNAME} hit test timeout" /usr/share/restraint/plugins/localwatchdog.d/10_localwatchdog; then
   echo 'echo "${RSTRNT_TASKNAME} hit test timeout, aborting it..." >> /dev/kmsg' >> /usr/share/restraint/plugins/localwatchdog.d/10_localwatchdog
fi

if ! cp -rf plugins /usr/share/restraint/; then
    echo "FAIL to copy plugins"
    rstrnt-report-result "${RSTRNT_TASKNAME}" FAIL 1
    rstrnt-abort -t recipe
fi
# Make sure the plugins have exec permission
chmod -R +x /usr/share/restraint/plugins
