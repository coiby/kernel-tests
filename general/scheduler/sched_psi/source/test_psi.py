import os
from lib import *
import time
def main():
    time.sleep(15)
    taskname = os.getenv("PSI_TEST_OPTION_TASK_NAME")
    cg = os.getenv("PSI_TEST_OPTION_CG")
    cgpath = os.getenv("PSI_TEST_OPTION_CG_PATH")
    cg1 = os.getenv("PSI_TEST_OPTION_CG1_PATH")
    cg2 = os.getenv("PSI_TEST_OPTION_CG2_PATH")
    if cg == 'nocg2':
        beakerlog("============ Plain PSI test ============")
        if psi_works(taskname,cg):
            exit(0)
        else:
            exit(1)
    elif cg == "cg2":
        beakerlog("============ CGroup2 sub tree PSi test ============")
        if psi_works(taskname,cgpath):
            exit(0)
        else:
            exit(1)
    elif cg == "cg2_p":
        beakerlog("============ CGroup2 parallel sub tree PSI test ============")
        if psi_cg2_parallel(cg1,cg2,taskname):
            exit(0)
        else:
            exit(1)
    elif cg == 'trigger':
        beakerlog("============ PSI trigger test ============")
        if trigger():
            exit(0)
        else:
            exit(1)
if __name__ == "__main__":
    main()


