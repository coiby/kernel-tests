#!/usr/bin/python3
from __future__ import print_function
import subprocess
import os
import sys
import time

command = "ipmitool"
options = (["sensor", "-v sensor", "sdr", "fru", "sel clear", "event 1",
           "sel", "sel list", "sel elist", "sel time", "sel time get",
           "pef status", "pef policy list", "pef capabilities","pef policy info"
           "sol", "channel info", "session", "sunoem", "picmg", "firewall",
           "firewall info", "mc info", "mc selftest", "chassis status", 
           "chassis power status", "sdr dump sdr.out", "sel save sel.out",
           "event file sel.out", "sel writeraw selraw.out", "sel readraw selraw.out"])


# Workaround for ACPI Error from https://access.redhat.com/solutions/49225
os.system('journalctl --dmesg | grep -i "ACPI Error" > error.log')
with open('error.log', 'r') as dmesg:
  if len(dmesg.readlines()):
    os.system('modprobe -r acpi_power_meter')
    os.system('modprobe acpi_ipmi')
    os.system('modprobe acpi_power_meter')

err = False
# Execute all options in the list
for option in options:
  try:
     print("********** Running: " + command + " " + option + " **********")
     subprocess.check_call(command + " " + option, shell=True)
     print("PASS: " + command + " " + option + " succeeded!\n")
     if option == "sel clear":
         time.sleep(5)
  except subprocess.CalledProcessError as e:
     print("FAIL: " + command + " " + option + " failed!\n", file=sys.stderr)
     err = True

# Print SDR records and entity IDs, save to a file, and retrieve by entity ID
print("********** Dump SDR entity ID to a file, retrieve by ID **********")
os.system('ipmitool sdr elist | cut -c 31-36 | sort | uniq > sdr-elist.txt')
try:
   f = open('sdr-elist.txt')
   for line in f:
      #print line
      subprocess.check_call(command + ' sdr entity' + " " + line, shell=True)
   f.close()
   print("PASS: SDR records were successfully printed\n")
except subprocess.CalledProcessError as e:
   print("FAIL: SDR entities failed to print", file=sys.stderr)
   err = True

# Verify no errors are aseen in the logs
print("********** Verify no errors are seen in the logs **********")
os.system('journalctl --dmesg | grep -i ipmi > error.log')
try:
   try:
      subprocess.check_call('! egrep -i "ACPI Error" error.log', shell=True)
   except subprocess.CalledProcessError as e:
      print("LOG: ACPI Error ignored")
   subprocess.check_call('! egrep -i "error|fail|warn" error.log | grep -v "ACPI Error"', shell=True)
   print("PASS: No IPMI related failures found\n")
except subprocess.CalledProcessError as e:
   print("FAIL: IPMI related failures were seen in the logs", file=sys.stderr)
   err = True

if err:
   sys.exit(1)
