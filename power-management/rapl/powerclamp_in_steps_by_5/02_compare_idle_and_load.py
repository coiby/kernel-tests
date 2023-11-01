#!/usr/bin/python

'''
Uses data (in file power.tmp - originally from turbostat) from previous run.
Checks if reported power consumption matches during idle is not significantly
bigger than under load. Loads should be in ascending order.

Accepts two parameters - the first is how many records should be in file
(default = 2), the second is the file (default = "power.tmp").

The single fail doesn't mean hard no-go.

If it fails, it's probably a problem. But if it fails in a few percents of runs
(on the same machine), It can be due to same load from test system or unexpected
run of daemon also.

Author:  Erik Hamera alias lhc
contact: lhc (at) redhat (dot) com
         ehamera (at) redhat (dot) com
License: GNU GPL
'''

power_file="power.tmp"

#When power1 should be less, than power2, there is some range for rounding errors,
#random daemons started incidentally when there was expected idle run and things like
#that, so the comparison is done that way: ( power1 < power2 * acceptable_error )
acceptable_error=1.2

import os
import os.path
import sys

warn_file="warn.tmp"

# MAIN

core_data=[]

if len(sys.argv) < 2:
        records=2
else:
        records=int(sys.argv[1])

if len(sys.argv) < 3:
        data_file="power.tmp"
else:
        data_file=str(sys.argv[2])

#open warn file
w = open(warn_file, 'a+')

#read data
if not os.path.isfile(data_file):
        print "No datafile - maybe not an error, just HW isn't supporting reading of power"
        w.write("No datafile - maybe not an error, just HW isn't supporting reading of power")
        w.close()
        sys.exit(0)
fdata = open(data_file, 'r')

error = 0

data = fdata.readlines()
fdata.close()

if len(data) < records:
        print 'Not enough records in datafile'
        w.write('Not enough records in datafile')
        w.close()
        sys.exit(0)

for i in range(len(data) - 1):
        if float(data[i]) > float(data[i+1]) * acceptable_error:
                print 'Much higher power consumption when lesser is expected. ', float(data[i]), ' should be lesser, than ', float(data[i+1])
                error+=1
        else:
                print 'O.K. ', float(data[i]), 'is lesser than', float(data[i+1]), '*', acceptable_error, ' (acceptable error).'

if error > 0:
        print
        print "An error occured. But the single fail doesn't mean hard no-go."
        print "It's probably a problem. But if it fails in a few percents of runs"
        print "on the same machine, it can be due to same load from test system or"
        print "unexpected run of daemon also."
else:
        print
        print "PASSED - logged power values are in ascending order (within defined error range", acceptable_error, ")."

w.close()
sys.exit(error)
