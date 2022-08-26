#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <stdio.h>
#include <time.h>
#include <pthread.h>
#include <stdint.h>
#include <inttypes.h>

/* Parameters for the Linux kernel ABI for CPU clocks.  */

#define CPUCLOCK_PID(clock)             ((pid_t) ~((clock) >> 3))
#define CPUCLOCK_PERTHREAD(clock) \
        (((clock) & (clockid_t) CPUCLOCK_PERTHREAD_MASK) != 0)
#define CPUCLOCK_PID_MASK       7
#define CPUCLOCK_PERTHREAD_MASK 4
#define CPUCLOCK_WHICH(clock)   ((clock) & (clockid_t) CPUCLOCK_CLOCK_MASK)
#define CPUCLOCK_CLOCK_MASK     3
#define CPUCLOCK_PROF           0
#define CPUCLOCK_VIRT           1
#define CPUCLOCK_SCHED          2
#define CPUCLOCK_MAX            3

#define MAKE_PROCESS_CPUCLOCK(pid, clock) \
        ((~(clockid_t) (pid) << 3) | (clockid_t) (clock))
#define MAKE_THREAD_CPUCLOCK(tid, clock) \
        MAKE_PROCESS_CPUCLOCK((tid), (clock) | CPUCLOCK_PERTHREAD_MASK)


static pthread_barrier_t barrier;

/* Help advance the clock.  */
static void *
chew_cpu (void *arg)
{
  pthread_barrier_wait (&barrier);
  while (1);

  return NULL;
}

/* Don't use the glibc wrapper.  */
static int
do_nanosleep (int flags, const struct timespec *req)
{
  clockid_t clock_id = MAKE_PROCESS_CPUCLOCK (0, CPUCLOCK_SCHED);

  return syscall (SYS_clock_nanosleep, clock_id, flags, req, NULL);
}

static int64_t
tsdiff (const struct timespec *before, const struct timespec *after)
{
  int64_t before_i = before->tv_sec * 1000000000ULL + before->tv_nsec;
  int64_t after_i = after->tv_sec * 1000000000ULL + after->tv_nsec;

  return after_i - before_i;
}

int
main (void)
{
  int result = 0;
  pthread_t th;

  pthread_barrier_init (&barrier, NULL, 2);

  if (pthread_create (&th, NULL, chew_cpu, NULL) != 0)
    {
      perror ("pthread_create");
      return 1;
    }

  pthread_barrier_wait (&barrier);

  /* The test.  */
  struct timespec before, after, sleeptimeabs;
  int64_t sleepdiff, diffabs;
  const struct timespec sleeptime = { .tv_sec = 0, .tv_nsec = 100000000 };

  /* The relative nanosleep.  Not sure why this is needed, but its presence
 *      seems to make it easier to reproduce the problem.  */
  if (do_nanosleep (0, &sleeptime) != 0)
    {
      perror ("clock_nanosleep");
      return 1;
    }

  /* Get the current time.  */
  if (clock_gettime (CLOCK_PROCESS_CPUTIME_ID, &before) < 0)
    {
      perror ("clock_gettime[2]");
      return 1;
    }

  /* Compute the absolute sleep time based on the current time.  */
  uint64_t nsec = before.tv_nsec + sleeptime.tv_nsec;
  sleeptimeabs.tv_sec = before.tv_sec + nsec / 1000000000;
  sleeptimeabs.tv_nsec = nsec % 1000000000;

  /* Sleep for the computed time.  */
  if (do_nanosleep (TIMER_ABSTIME, &sleeptimeabs) != 0)
    {
      perror ("absolute clock_nanosleep");
      return 1;
    }

  /* Get the time after the sleep.  */
  if (clock_gettime (CLOCK_PROCESS_CPUTIME_ID, &after) < 0)
    {
      perror ("clock_gettime[3]");
      return 1;
    }

  /* The time after sleep should always be equal to or after the absolute sleep
 *      time passed to clock_nanosleep.  */
  sleepdiff = tsdiff (&sleeptimeabs, &after);
  if (sleepdiff < 0)
    {
      printf ("absolute clock_nanosleep woke too early: %" PRId64 "\n",
	      sleepdiff);
      result = 1;
    }

  /* The difference between the timestamps taken before and after the
 *      clock_nanosleep call should be equal to or more than the duration of the
 *           sleep.  */
  diffabs = tsdiff (&before, &after);
  if (diffabs < sleeptime.tv_nsec)
    {
      printf ("clock_gettime difference too small: %" PRId64 "\n", diffabs);
      result = 1;
    }

  pthread_cancel (th);

  return result;
}

