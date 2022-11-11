#!/usr/bin/python

'''
Uses data (in files turbostat_test_output.tmp and perf_test_output.tmp)
from previous run of these tools.
Checks if reported power consumption matches within rounding error range.

Accepts 1 or 2 parameters - the first is filename with turbostat and
the second is perf output.

Data are read from the same MTRR registers, so fail of this test indicates
bug in turbostat or perf (or both of course).

This test can't catch bug in MTRR registers, nor exactly the same bug in
turbostat and perf both.

Author:  Erik Hamera alias lhc
contact: lhc (at) redhat (dot) com
         ehamera (at) redhat (dot) com
License: GNU GPL
'''

import os
import re
import sys


#file for warnings - like "unable to test, because HW is old" and similar
warn_file="warn.tmp"

#file for log power consumption reported by turbostat - for next analysis
power_file="power.tmp"

no_aperf=re.compile(r"\s*turbostat: No APERF")
no_tsc=re.compile(r"\s*turbostat: No invariant TSC")

headline_1socket=re.compile(r"\s+Core")
headline_moresockets=re.compile(r"\s+Package")
avgstat=re.compile(r"\s+-\s+-")
corestat=re.compile(r"\s+[0-9]+\s+[0-9]+")
time=re.compile(r"[0-9.]+\s+sec")

joules=re.compile(r".*Joules.*")
seconds=re.compile(r".*seconds.*")

dot=re.compile(r".*[.]")
star_in_number=re.compile(r"[0-9]*\*")

def found_half_lsn(p1):
    '''founds half on the least significant number'''
    #accepts string which contains number
    #returns float
    if dot.match(p1):
        mkhalf='5'
    else:
        mkhalf='.5'
    half_lsn=float(p1+mkhalf)-float(p1)
    return half_lsn

def div_and_compare_with_error(A, t, P):
    half_lsn_A=found_half_lsn(A)
    half_lsn_P=found_half_lsn(P)
    #why there is no half lsn of t? It's simple:
    #A and P has precision 0.01 only, but t has 9 numbers behind decimal point,
    #so the rounding error of t ins't able to interfere with the test

    P_max=float(P) + half_lsn_P
    P_min=float(P) - half_lsn_P

    A_div_t_max=(float(A) + half_lsn_A)/float(t)
    A_div_t_min=(float(A) - half_lsn_A)/float(t)

    # A_div_t is physically the same think as P, but obtained by another tool.
    # Because the value is obtained from the same CPU at almst the same time,
    # it must be the same. Therefore error ranges (existing due to rounding) must overlap.

    print 'turbostat rounding error range is: ', P_min, '-', P_max, 'W'
    print 'perf rounding error range is:', A_div_t_min, '-', A_div_t_max, 'W'
    if (P_max < A_div_t_min or P_min > A_div_t_max):
        #false
        return 0
    else:
        #true
        return 1

def name2index(regular_expression_name):
    '''Returns index to headline (and data both) to given string or -1 if the string
    isn't present.
    WARNING: there is global variable headline. This function reads it only. '''
    regsearch=re.compile(regular_expression_name)
    i=0
    err=1
    for name in headline:
        if regsearch.match(name):
            err=0
            break
        i=i+1
    if err:
        #the name isn't here
        return -1
    else:
        return i

def name2value(data, regular_expression_name):
    '''Returns value according to the given string's position in the headline in the data.'''
    idx=name2index(regular_expression_name)
    if idx==-1:
        #There is adding or multiplying in the code, so add 0 for nonexistent field
        #makes sense and simplyfies the code.
        #In case of needness, test can be done by name2index().
        return 0
    str_value=data[idx]
    if str_value=='-':
        #It's in number of package, core or CPU at the first line only. There is no
        #computation done with these so anything can be returned.
        #This whole if is there just to avoid error if someone will run it in cycle
        #through whole data.
        return -1
    else:
        return float(str_value)

def name2strvalue(data, regular_expression_name):
    '''Returns value string according to the given string's position in the headline in the data.'''
    idx=name2index(regular_expression_name)
    if idx==-1:
        #There is adding or multiplying in the code, so add 0 for nonexistent field
        #makes sense and simplyfies the code.
        #In case of needness, test can be done by name2index().
        return '0'
    return data[idx]


# MAIN

core_data=[]

error=0
#each error will increment this variable

#file_store
if len(sys.argv) < 2:
        file_store="turbostat_test_output.tmp"
else:
        file_store=str(sys.argv[1])

if len(sys.argv) < 3:
        file_store_2="perf_test_output.tmp"
else:
        file_store_2=str(sys.argv[2])

block=1
#1 = description
#2 = average
#3 = cores
#4 = time

#read turbostat output
p = os.popen('cat '+file_store,"r")

#open warn file
w = open(warn_file, 'a+')

line = p.readline()
while block<5:
    if not line: break
    #print '###', line
    if (block == 1):
        if headline_1socket.match(line):
            block+=1;
            multiple_packages=0
            headline=re.split('\s+', line)
            line = p.readline()
        elif headline_moresockets.match(line):
            block+=1;
            multiple_packages=1
            headline=re.split('\s+', line)
            line = p.readline()
        elif no_aperf.match(line):
            print "No APERF, can't test anything."
            w.write('check: no APERF\n')
            w.close()
            sys.exit(0)
            #sys.exit(untested)
        elif no_tsc.match(line):
            print "No TSC, can't test anything."
            w.write('check: no TSC\n')
            w.close()
            sys.exit(0)
            #sys.exit(untested)
        else:
            print 'data read: block 1 error'
            error+=1
            break
    elif (block == 2):
        if avgstat.match(line):
            #extract data
            avg_data=re.split('\s+', line)
            core_data.append(avg_data)
            block+=1;
            line = p.readline()
        else:
            print 'data read: block 2 error'
            error+=1
            break
    elif (block == 3):
        if corestat.match(line):
            #extract data
            core_data.append(re.split('\s+', line))
            line = p.readline()
        else:
            block+=1;
    elif (block == 4):
        if time.match(line):
            exectime=re.split('\s+', line)
            block+=1
        else:
            print 'data read: block 4 error'
            error+=1
            break


corwatt=name2strvalue(avg_data, r"CorWatt")
#some older CPUs don't report CorWatt - there is nothing to test
if (corwatt == 0): #there is no CorWatt probably
    if (name2index(r"CorWatt") == -1): #no CorWatt definitelly
        print "There is no CorWatt in turbostat's output (too old CPU probably). Nothing to test."
        w.write('check: no CorWatt\n')
        w.close()
        sys.exit(0)
        #sys.exit(untested)

if star_in_number.match(corwatt):
    #I don't know how to handle this and there is nothing in manual. It's very hard to google anything
    #containing the * character. There is possibility, that it's warning and not fail. OTOH perf reports
    #correct data in these situations, so why turbostat can't?
    print "The star (*) character in corwatt. Don't know what it means => FAIL"
    #Without immediate exit it will fail during converting string like '2**' to numbers.
    sys.exit(1)

#open power file and write CorWatt for next test
pwr = open(power_file, 'a+')
pwr.write(corwatt+'\n')
pwr.close

# Read perf output
block=1
#1 = Joules
#2 = time

q = os.popen('cat '+file_store_2,"r")

energy_line_exist=0
time_line_exist=0

line = q.readline()
while block<3:
    if not line: break
    if (block == 1):
        if joules.match(line):
            energy_line=re.split('\s+', line)
            energy_line_exist=1
            block+=1
        line = q.readline()
    if (block == 2):
        if seconds.match(line):
            time_line=re.split('\s+', line)
            time_line_exist=1
            block+=1
        line = q.readline()

if not energy_line_exist:
    print 'data read error: no energy in perf output'
    error+=1
    print 'Error count is', error
    w.write('check: no energy line in perf output.\n')
    w.close()
    sys.exit(0)

perf_energy=energy_line[1]

if not time_line_exist:
    print 'data read error: no time in perf output'
    error+=1
    print 'Error count is', error
    w.write('check: no energy line in perf output.\n')
    w.close()
    sys.exit(0)

perf_time=time_line[1]

print 'turbostat reports', corwatt, ' W, perf reports;', perf_energy, ' J and time', perf_time, 's.'

if div_and_compare_with_error(perf_energy, perf_time, corwatt):
    print 'OK'
else:
    error+=1
    print 'ERROR'


print 'Error count is', error
sys.exit(error)
