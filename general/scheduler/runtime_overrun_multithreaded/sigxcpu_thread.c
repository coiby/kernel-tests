#include <linux/kernel.h>
#include <pthread.h>
#include <sched.h>
#include <semaphore.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sysexits.h>
#include <time.h>
#include <unistd.h>

#define TEST1_DESC                                                             \
  "test#1 - main thread runtime overrun generates SIGXCPU with "               \
  "SCHED_FLAG_DL_OVERRUN flag applied to the main thread,\n"                   \
  "and child thread overrun doesn't generate the signal "                      \
  "while only main have the flag.\n\n"

#define TEST2_DESC                                                             \
  "test#2 - main thread runtime overrun doesn't generate SIGXCPU "             \
  "with no flag applied to main,\n"                                            \
  "and main thread overrun doesn't generate the signal "                       \
  "with the flag applied to child thread.\n\n"

#define TEST3_DESC                                                             \
  "test#3 - child thread runtime overrun generates SIGXCPU "                   \
  "with the flag applied to the child thread,\n"                               \
  "and child thread still generates the signal while the flag is "             \
  "applied to both child and main.\n\n"

#define TEST4_DESC                                                             \
  "test#4 - child thread runtime overrun doesn't generate SIGXCPU "            \
  "with no flag applied to child,\n"                                           \
  "and child doesn't generate with the flag "                                  \
  "applied to main but not to child.\n\n"

#define SCHED_FLAG_NONE 0x00
#define SCHED_FLAG_DL_OVERRUN 0x04
#define SCHED_DEADLINE 6
// for readability
#define PRODUCE_OVERRUN 1
#define NO_OVERRUN 0
#define YIELD 1
#define NO_YIELD 0
#define CHILD 1
#define MAIN 0
#define BUSY_TIME_MS 500
#define EX_TESTFAIL 1

/* sched_attr is not defined in glibc < 2.41 */
#ifndef SCHED_ATTR_SIZE_VER0
struct sched_attr {
  __u32 size;
  __u32 sched_policy;
  __u64 sched_flags;
  __s32 sched_nice;
  __u32 sched_priority;
  __u64 sched_runtime;
  __u64 sched_deadline;
  __u64 sched_period;
};

static inline long sched_setattr(pid_t pid, const struct sched_attr *attr,
                                 unsigned int flags) {
  return syscall(__NR_sched_setattr, pid, attr, flags);
}

#define SCHED_ATTR_SIZE_VER0 48
#endif
/* end sched_attr definition*/

// globals
sem_t child_thread_semaphore;
pthread_t main_thread_id, service_thread_id, child_thread_id;
sigset_t set;

static volatile int overrun_count = 0;

struct sched_attr attr = {.size = sizeof(struct sched_attr),
                          .sched_policy = SCHED_DEADLINE,
                          .sched_flags = SCHED_FLAG_NONE,
                          .sched_priority = 0,
                          .sched_nice = 0,
                          .sched_runtime = 50 * 1000000Ul, // 50ms
                          .sched_period = 100 * 1000000Ul,
                          .sched_deadline = 100 * 1000000Ul};

// if 'overrun' is true, wasting cpu cycles to produce a runtime overrun.
// otherwise yielding using sleep. time is in ms.
static void busy_wait(uint16_t time, _Bool overrun) {
  clock_t start_time = clock();
  do
    if (!overrun)
      usleep(1);
  while (time * CLOCKS_PER_SEC / 1000 > (clock() - start_time));
}

// apply policy to calling thread, fail if unable.
void sched_setattr_or_die() {
  if (sched_setattr(0, &attr, 0) < 0) {
    perror("sched_setattr unable to set sched policy");
    exit(EX_NOPERM);
  }
}

void yield_or_die() {
  if (sched_yield() != 0) {
    pthread_self() == main_thread_id
        ? perror("failed to yield main thread")
        : perror("failed to yield child thread");
    exit(EX_OSERR);
  }
}

void join_child_thread() {
  printf("main: waiting for child thread to return\n");
  int join_err;
  if ((join_err = pthread_join(child_thread_id, NULL)) != 0) {
    fprintf(stderr, "failed to join child thread, error:%d\n\n", join_err);
    exit(EX_OSERR);
  }
}

void release_child_semaphore_or_die(_Bool yield) {
  pthread_self() == main_thread_id
      ? printf("main: allowing child thread to apply policy%s\n", yield ? "" : " and overrun")
      : printf("child: releasing semaphore to allow main thread\n");
  if (sem_post(&child_thread_semaphore) != 0) {
    perror("failed to release child thread semaphore");
    exit(EX_OSERR);
  }
  yield ? yield_or_die() : join_child_thread();
}

void apply_policy_to_thread(_Bool signal_child, int flag, _Bool yield) {
  attr.sched_flags = flag;
  char *flag_name;
  if (flag == SCHED_FLAG_DL_OVERRUN)
    flag_name = "FLAG_DL_OVERRUN";
  else
    flag_name = "No Flag";
  if (signal_child) {
    printf("signalling child thread to apply %s\n", flag_name);
    release_child_semaphore_or_die(yield);
  } else {
    printf("applying %s\n", flag_name);
    sched_setattr_or_die();
  }
}

void collect_child_semaphore() {
  pthread_self() == main_thread_id
      ? printf("main: receiving a child thread semaphore\n")
      : printf("child: waiting for a semaphore\n");
  sem_wait(&child_thread_semaphore);
}

// signal handler thread
static void *service_thread(void *arg) {
  siginfo_t info;
  sigset_t *sigset = arg;
  int sig;

  for (;;) {
    sig = sigwaitinfo(sigset, &info);
    switch (sig) {
    case -1:
      perror("service thread sigwaitinfo");
      exit(EX_SOFTWARE);
    case SIGXCPU:
      overrun_count++;
      break;
    default:
      fprintf(stderr, "unexpected signal by sigwaitinfo: %d\n", sig);
      exit(EX_OSERR);
    }
  }
}

void thread_overrun() {
  printf("%s: producing thread overrun\n",
         pthread_self() == main_thread_id ? "main" : "child");
  busy_wait(BUSY_TIME_MS, PRODUCE_OVERRUN);
}

static void *child_thread(void *arg) {
  (void)arg;
  // waits for the main thread to allow setting the policy
  collect_child_semaphore();

  printf("child: applying policy\n");
  sched_setattr_or_die();
  release_child_semaphore_or_die(YIELD);

  // picks up the semaphore, either from the main thread,
  // or its own from sem_post above in case that
  // main didn't used it while child thread yielded
  collect_child_semaphore();
  thread_overrun();
  printf("child: thread finished\n");
  return NULL;
}

// nothing personal
void kill_sem() { sem_destroy(&child_thread_semaphore); }

// set signal handlers
// create a service thread
void init_handlers() {
  struct sigaction act = {0};
  act.sa_handler = SIG_IGN;
  if (sigaction(SIGPIPE, &act, NULL) == -1) {
    perror("failed to set SIGPIPE signal handler");
    exit(EX_NOPERM);
  }

  sigemptyset(&set);
  sigaddset(&set, SIGXCPU);
  if (pthread_sigmask(SIG_BLOCK, &set, NULL) != 0) {
    perror("failed to mask signals");
    exit(EX_OSERR);
  }

  if (pthread_create(&service_thread_id, NULL, &service_thread, &set) != 0) {
    perror("failed to start a signal handling service thread");
    exit(EX_OSERR);
  }
}

void create_child_thread_or_die() {
  if (pthread_create(&child_thread_id, NULL, &child_thread, &set) != 0) {
    perror("failed to start a child thread");
    exit(EX_OSERR);
  }
}

// init a locked semaphore for the child thread to use,
// scheduling destruction on exit, and create a child thread.
void init_child_thread() {
  if (sem_init(&child_thread_semaphore, 0, 0) != 0) {
    perror("failed to init a semaphore");
    exit(EX_OSERR);
  }
  atexit(kill_sem);
  create_child_thread_or_die();
}

// verify and reset the counter
void verify_signal(_Bool expected, char *msg) {
  if (expected ? overrun_count < 1 : overrun_count > 0) {
    fprintf(stderr, "test failed: with %s thread overrun %sexpected SIGXCPU\n\n", 
            msg, expected ? "haven't produced " : "produced un");
    exit(EX_TESTFAIL);
  }
  printf("success: with %s thread overrun SIGXCPU %s detected.\n", 
         msg, expected ? "is" : "not");
  overrun_count = 0;
}

void pass(int test) {
  printf("test #%d passed\n\n", test);
  exit(EX_OK);
}

// test cases below
void test_main_flagged_overrun() {
  // set the flag, produce an overrun, verify SIGXCPU is produced
  apply_policy_to_thread(MAIN, SCHED_FLAG_DL_OVERRUN, NO_YIELD);
  thread_overrun();
  verify_signal(PRODUCE_OVERRUN, "main thread flag set, main");

  // set flag to none and signal child thread to set the policy,
  // and to produce an overrun. wait for child thread to complete.
  // verify no additional SIGXCPU signals produced
  apply_policy_to_thread(CHILD, SCHED_FLAG_NONE, NO_YIELD);
  verify_signal(NO_OVERRUN, "main thread flag set, child");
  pass(1);
}

void test_main_not_flagged_overrun() {
  // apply the default unset flag policy to main thread and overrun
  sched_setattr_or_die();
  thread_overrun();
  verify_signal(NO_OVERRUN, "no main thread flag, main");

  // set the flag, release a semaphore to signal the child thread to
  // apply the policy, yield so child picks up the semaphore
  // and wait for it to release the semaphore back once
  // the policy is applied
  // produce overrun in main thread, verify still no signal
  apply_policy_to_thread(CHILD, SCHED_FLAG_DL_OVERRUN, YIELD);
  collect_child_semaphore();
  thread_overrun();
  verify_signal(NO_OVERRUN, "child thread flag, main");
  pass(2);
}

void test_child_flagged_overrun() {
  // signal and wait for the child thread to set scheduling policy
  // and to produce an overrun
  apply_policy_to_thread(CHILD, SCHED_FLAG_DL_OVERRUN, NO_YIELD);
  verify_signal(PRODUCE_OVERRUN, "child thread flag set, child");

  // rerun child, apply policy to both threads,
  // allow child thread overrun and wait for child to return
  create_child_thread_or_die();
  sched_setattr_or_die();
  release_child_semaphore_or_die(NO_YIELD);
  verify_signal(PRODUCE_OVERRUN, "flag applied to both threads, child");
  pass(3);
}

void test_child_not_flagged_overrun() {
  // signal child thread to set scheduling policy and to produce an overrun
  release_child_semaphore_or_die(NO_YIELD);
  verify_signal(NO_OVERRUN, "no child flag set, child");

  // rerun child, apply flag to main, and overrun child with no flag
  create_child_thread_or_die();
  apply_policy_to_thread(MAIN, SCHED_FLAG_DL_OVERRUN, NO_YIELD);
  apply_policy_to_thread(CHILD, SCHED_FLAG_NONE, NO_YIELD);
  verify_signal(NO_OVERRUN, "flag applied to main, child");
  pass(4);
}

int main(int argc, char *argv[]) {
  if (argc > 1) {
    main_thread_id = pthread_self();
    init_handlers();
    init_child_thread();

    int test_number;
    switch (test_number = atoi(argv[1])) {
    case 1:
      printf(TEST1_DESC);
      test_main_flagged_overrun();
    case 2:
      printf(TEST2_DESC);
      test_main_not_flagged_overrun();
    case 3:
      printf(TEST3_DESC);
      test_child_flagged_overrun();
    case 4:
      printf(TEST4_DESC);
      test_child_not_flagged_overrun();
    default: // if wrong argument is applied
      fprintf(stderr, "e:unexpected test number %d\n", test_number);
      exit(EX_USAGE);
    }
  } else {
    printf("usage: %s <test number>\n" TEST1_DESC TEST2_DESC TEST3_DESC TEST4_DESC, argv[0]);
    exit(EX_NOINPUT);
  }
}
