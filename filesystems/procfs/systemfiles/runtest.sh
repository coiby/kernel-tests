#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh || exit 1


SYSTEM_FILES="/proc/filesystems"
OUTPUT_FILE="/var/tmp/filesystem_list.txt"
rlRun_LOG=""

rlJournalStart
    rlPhaseStartTest  "Listing and formatting filesystems"

      rlAssertExists "$SYSTEM_FILES"
      # Run the command and capture output
      rlRun -s "cat $SYSTEM_FILES | awk '{print \$NF}' | sort"
      echo -n "filesystem_list=[" > "$OUTPUT_FILE"
      awk '{printf "\047%s\047, ", $1}' "$rlRun_LOG" | sed 's/, $//' >> "$OUTPUT_FILE"
      echo "]" >> "$OUTPUT_FILE"
      cat "$OUTPUT_FILE"  # Display formatted output

    rlPhaseEnd

    rlPhaseStartCleanup
      # Clean up the temporary output file
      rlRun "rm -f $rlRun_LOG $OUTPUT_FILE" 0 "Remove temporary files"
    rlPhaseEnd
rlJournalEnd
