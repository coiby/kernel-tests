#!/usr/bin/python
# detects SD reader and does tests with dt and copy/compare.

from cmd_helper import *
import logging
import sys
import shutil
import optparse
import time

usage = "usage: %prog [options] arg"
parser = optparse.OptionParser(usage)
parser.add_option("-d", "--dev", dest="test_dev", default="/dev/mmcblk0",
                  help="Specify the device to use, default is /dev/mmcblk0", metavar="FILE",
                  type="string", action="store")
parser.add_option("-t", "--tld", dest="tld", default="/mnt/testarea/SD-card",
                  help="Specify the top level directory device to use, default is /mnt/testarea/SD-card",
                  metavar="DIR", type="string", action="store")
parser.add_option("-s", "--size", dest="test_size", default=1073741824,
                  help="Specify the amount of data to use for testing, default is smaller of 1GB or the device size",
                  metavar="DIR", type="int", action="store")
(options, args) = parser.parse_args()
test_dev = options.test_dev
tld = options.tld
test_size = options.test_size
mount_pt = tld + "/SD_mnt"
scratch_dir = tld + "/scratch"
log_dir = tld + "/logs"

logger = logging.getLogger()
handler = logging.StreamHandler()
logfh = logging.FileHandler(log_dir + "/test_sd.log")
formatter = logging.Formatter(
        '%(asctime)s %(name)-4s %(levelname)-2s %(message)s')
handler.setFormatter(formatter)
logfh.setFormatter(formatter)
logger.addHandler(handler)
logger.addHandler(logfh)
logger.setLevel(logging.DEBUG)

def check_working_dirs():
    for d in tld, mount_pt, scratch_dir:
        if not os.path.isdir(mount_pt):
            raise OSError("moutn point: {0} does not exist".format(mount_pt))

def run_test():
    cw = cmd_wrapper()
    mydt = dt()
    iotype = ("sequential", "random")
    dt_results = {}
    sha1sum_results = {}
    if test_size != 1073741824:
        mydt.test_size = test_size
    cw.drop_caches()
    for t in iotype:
        dt_results[t] = mydt.run(mount_pt=mount_pt, iotype=t, test_size=mydt.test_size)
        cw.drop_caches()
    logger.info("copying " + mount_pt + '/' + mydt.testfile + " to " + scratch_dir)
    t_start = time.time()
    try:
        shutil.copy(mount_pt + '/' + mydt.testfile, scratch_dir)
    except shutil.Error as e:
        logger.warning('Error: %s' % e)
    except IOError as e:
        logger.warning('Error: %s' % e.strerror)
    t_end = time.time()
    logger.info("Copy took " + str(t_end - t_start) + " seconds")
    cw.drop_caches()
    cmd = "sha1sum {0}/{1} {2}/{3}".format(mount_pt, mydt.testfile, scratch_dir, mydt.testfile)
    sha1sum_out = cw.run_cmd(cmd)
    results = [result.partition("  ") for result in sha1sum_out[0].split("\n")[:-1]]
    for result in results:
        v, _, k = result
        sha1sum_results[k] = v
    return sha1sum_results, dt_results

def main(test_dev):
    check_working_dirs()
    bd = block_dev_info()
    cw = cmd_wrapper()
    test_dev = re.search(bd.last_slash_pat, test_dev).group(0)
    if test_dev in bd.detected_devs:
        # run our test
       # if bd.get_size_in_bytes() < mydt.test_size:
       #     mydt.test_size = bd.get_size_in_bytes(test_dev) - 2048
        if not bd.is_partition(test_dev):
            # Lets find the biggest partition and use that
            parts = [p for p in bd.detected_devs if p.startswith(test_dev) and bd.is_partition(p)]
            test_dev = bd.get_largest_block_dev(parts)
        with handle_mount(test_dev, mount_pt) as m:
            results = run_test()
    else:
        print "{0} not detected".format(test_dev)
        return 1
    #now evaluate our results
    sha1_result, dt_result = results
    if len(set(sha1_result.values())) == 1:
        sha1_pass = True
    else:
        sha1_pass = False
    # print sha1_pass
    # score dt results

if __name__ == "__main__":
    sys.exit(main(test_dev))
