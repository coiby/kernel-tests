import os
import time
import math
import sys
def get_cpus():
    cmd = "grep -w ^processor -c /proc/cpuinfo"
    cmdline_obj = os.popen(cmd)
    cmdline = (cmdline_obj.readlines())[0]
    cmdline = cmdline[:-1]
    return int(cmdline)

cpu_num = get_cpus()
def get_test(option):
    psi_io_large = "stress-ng --copy-file %d --timeout 40s"%(cpu_num*2)
    psi_io_small = "stress-ng --copy-file %d --timeout 40s"%(math.ceil(cpu_num/2*3))
    psi_memory_large = "./source/mem_stress"
    psi_memory_small = "./source/mem_stress"
    psi_cpu_large = "stress-ng --cpu %d --timeout 40s"%(math.ceil(cpu_num*2))
    psi_cpu_small = "stress-ng --cpu %d --timeout 40s"%(math.ceil(cpu_num/2*3))

    if option == "io_small" or option == "io":
        return psi_io_small
    elif option == "io_large":
        return psi_io_large
    elif option == "memory_large":
        return psi_memory_large
    elif option == "memory_small" or option == "memory" or option == "mem":
        return psi_memory_small
    elif option == "cpu_small" or option == "cpu":
        return psi_cpu_small
    elif option == "cpu_large":
        return psi_cpu_large

def beakerlog(string):
    cmd = ''' . /usr/share/beakerlib/beakerlib.sh
            rlLogInfo "%s"  '''%(string)
    os.system(cmd)

def beakereport(name,result):
    cmd = ''' . /usr/share/beakerlib/beakerlib.sh
            rlReport "%s" "%s" '''%(name,result)
    os.system(cmd)

def beakereportscore(name,result,score):
    cmd = ''' . /usr/share/beakerlib/beakerlib.sh
            rlReport "%s" "%s" %d '''%(name,result,score)
    os.system(cmd)

def beakersubmitfile(path,name):
    cmd = ''' . /usr/share/beakerlib/beakerlib.sh
            rlFileSubmit "%s" "%s" '''%(path,name)
    os.system(cmd)

def beakerwatchdog(cmd,timeout):
    cmd = ''' . /usr/share/beakerlib/beakerlib.sh
            rlWatchdog "%s" %d '''%(cmd,int(timeout))
    return os.system(cmd)

def run_psi(name,place):
    pid = os.fork()
    if pid == 0:
        #child
        print("wait for 3s...")
        time.sleep(3)
        taskname = get_test(name)
        beakerlog("Run :"+taskname)
        beakerlog("In : "+place)
        os.system(taskname)
        sys.exit(0)
    else:
        #parent
        if place != 'nocg2':
            os.system("echo %d > %s/cgroup.procs"%(pid,place))
            beakerlog("moved %d to cgroup:%s"%(pid,place))
        os.waitpid(pid,0)

def get_proc_pressure_avg10(test,path):
    return get_proc_pressure(test,path,10)

def get_proc_pressure_avg60(test,path):
    return get_proc_pressure(test,path,60)

def get_proc_pressure(test,path,avg_length):
    target = ""
    if path == 'nocg2':
        target = "/proc/pressure/%s"%(test)
    else:
        target = "%s/%s.pressure"%(path,test)
    print("get statistics from: "+target)
    f = open(target,"r")
    line = (f.readlines())[0]
    line = line[:-1]
    items = line.split(" ")
    for item in items:
        if item[0:5] == "avg"+str(avg_length):
            num = (item.split("="))[-1]
            return float(num)

def psi_works(test,path):
    pid = os.fork()
    if pid == 0:
        run_psi(test,path)
        sys.exit(0)
    else:
        if test.startswith("memory"):
            some_avg_1 = get_proc_pressure_avg10(test,path)
            print("some_avg_1:"+str(some_avg_1))

            some_avg_2 = 0.0
            duration = 0
            max_duration = 600
            tick_duration = 5
            peak_time = 0
            # Measure the peak memory pressure, taking up to 10m
            # This can happen on systems with large amounts of memory (hundreds of GB)
            while duration <= max_duration:
                time.sleep(tick_duration)
                pressure = get_proc_pressure_avg10(test,path)
                if pressure > some_avg_2:
                    some_avg_2 = pressure
                    peak_time = duration

                duration += tick_duration
                
                # Exit early if we have a significant reading (2% memory pressure)
                if some_avg_2 > (some_avg_1 + 2):
                    break
            beakerlog("Peak memory usage at %d seconds"%(peak_time))

        else:
            some_avg_1 = get_proc_pressure_avg10(test,path)
            print("some_avg_1:"+str(some_avg_1))
            time.sleep(35)
            some_avg_2 = get_proc_pressure_avg10(test,path)
        print("some_avg_2:"+str(some_avg_2))
        beakerlog("First reading: " + str(some_avg_1))
        beakerlog("Second reading: " + str(some_avg_2))
        os.waitpid(pid,0)
        place = ""
        if path == 'nocg2' :
            place = "/proc/pressure"
        else:
            place = path
        if some_avg_2 > some_avg_1 :
            beakereport("PSI %s test in %s "%(test,place),"PASS")
            return True
        else:
            beakereport("PSI %s test in %s "%(test,place),"FAIL")
            return False

def psi_cg2_parallel(cg1,cg2,test):
    pid = os.fork()
    if pid == 0:
        run_psi(test,cg1)
        sys.exit(0)
    else:
        if test.startswith("memory"):
            some_avg_cg1_1 = get_proc_pressure_avg10(test,cg1)
            some_avg_cg2_1 = get_proc_pressure_avg10(test,cg2)

            some_avg_cg1_2 = 0.0
            some_avg_cg2_2 = 0.0
            duration = 0
            max_duration = 600
            tick_duration = 5
            # Measure the peak memory pressure over 10 minutes
            while duration <= max_duration:
                time.sleep(tick_duration)
                pressure_1 = get_proc_pressure_avg10(test,cg1)
                if pressure_1 > some_avg_cg1_2:
                    some_avg_cg1_2 = pressure

                pressure_2 = get_proc_pressure_avg10(test,cg2)
                if pressure > some_avg_cg2_2:
                    some_avg_cg2_2 = pressure
                duration += tick_duration

                # Exit early if we have a significant reading (2% memory pressure)
                if some_avg_cg1_2 > (some_avg_cg1_1 + 2) and some_avg_cg2_2 > (some_avg_cg2_1 + 2):
                    break
        else:
            some_avg_cg1_1 = get_proc_pressure_avg10(test,cg1)
            some_avg_cg2_1 = get_proc_pressure_avg10(test,cg2)
            time.sleep(35)
            some_avg_cg1_2 = get_proc_pressure_avg10(test,cg1)
            some_avg_cg2_2 = get_proc_pressure_avg10(test,cg2)
        print("some_avg_cg1_1:"+str(some_avg_cg1_1))
        print("some_avg_cg2_1:"+str(some_avg_cg2_1))
        print("some_avg_cg1_2:"+str(some_avg_cg1_2))
        print("some_avg_cg2_2:"+str(some_avg_cg2_2))
        beakerlog("First reading cg1: " + str(some_avg_cg1_1))
        beakerlog("Second reading cg1: " + str(some_avg_cg1_2))
        beakerlog("First reading cg2: " + str(some_avg_cg2_1))
        beakerlog("Second reading cg2: " + str(some_avg_cg2_2))
        os.waitpid(pid,0)
        if some_avg_cg1_2 > some_avg_cg1_1 and some_avg_cg2_2 <= some_avg_cg2_1:
            beakereport("PSI parallel test in subsystem","PASS")
            return True
        else:
            beakereport("PSI parallel test in subsystem","FAIL")
            return False

def trigger():
    tests = [
        {"test":"io_large","path":"/proc/pressure/io","place":"nocg2"},
        {"test":"memory_large","path":"/proc/pressure/memory","place":"nocg2"},
        {"test":"cpu_large","path":"/proc/pressure/cpu","place":"nocg2"},

        {"test":"io_large","path":"/mnt/cgroup2/sub1/io.pressure","place":"/mnt/cgroup2/sub1"},
        {"test":"memory_large","path":"/mnt/cgroup2/sub1/memory.pressure","place":"/mnt/cgroup2/sub1"},
        {"test":"cpu_large","path":"/mnt/cgroup2/sub1/cpu.pressure","place":"/mnt/cgroup2/sub1"},

        {"test":"io_large","path":"/mnt/cgroup2/sub2/io.pressure","place":"/mnt/cgroup2/sub2"},
        {"test":"memory_large","path":"/mnt/cgroup2/sub2/memory.pressure","place":"/mnt/cgroup2/sub2"},
        {"test":"cpu_large","path":"/mnt/cgroup2/sub2/cpu.pressure","place":"/mnt/cgroup2/sub2"},
    ]
    counter = 0
    for item in tests:
        name = item["test"]
        path = item["path"]
        place = item["place"]
        pid = os.fork()
        if pid == 0:
            run_psi(name,place)
            exit(0)
        else:
            cmd_ex = "source/trigger %s"%(path)
            result = beakerwatchdog(cmd_ex,60)
            os.waitpid(pid,0)
            if result == 0:
                beakerlog(name+" in "+path+" triggered")
                counter += 1
    if counter>0:
        beakereportscore("PSI trigger test","PASS",counter)
        return True            
    else:
        beakereport("Maybe not enough stress for triggers.","WARN")
        return False

if __name__ == "__main__":
    trigger()
