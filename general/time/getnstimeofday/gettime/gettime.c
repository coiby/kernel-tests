#include <linux/init.h>
#include <linux/time.h>
#include <linux/errno.h>
#include <linux/module.h>
#include <linux/sched.h>
#include <linux/kthread.h>
#include <linux/cpumask.h>
#include <linux/smp.h>
#include <linux/topology.h>

/* TWEAKABLE SLEEP CONSTANTS */
#define NANOSECONDS_PER_SECOND 1000000000L
#define MILLISECONDS_PER_SECOND 1000
#define GETTIME_THREAD_INTERRUPTIBLE_SLEEP_MILLISECONDS MILLISECONDS_PER_SECOND * 2
#define GETTIME_TEST_INTERRUPTIBLE_SLEEP_MILLISECONDS MILLISECONDS_PER_SECOND * 10
#define GETTIME_TEST_WAIT_MILLISECONDS 100

/* Change this to 1 for lots of information in your dmesg */
#define BE_VERBOSE 0

/* (struct gettime_thread_data)
 * The information required to launch a gettime_thread
 *
 * @cpu: The cpu that the thread should be run on. This will be validated at the start of the thread
 *
 * @has_started: This value is zero unless the thread has already validated that it is running
 * 	on the correct cpu
 */
struct gettime_thread_data {
	int cpu ;
	unsigned int has_started ;
} ;

/* @seconds_to_nanoseconds
 * Convert a (time_t)value representing seconds to a (long)value reprsenting the equivalent nanoseconds
 *
 * Precondition: (time_t) is implemented on the host system as a signed integral type
 *
 * Postconditon: The @seconds argument is returned represented as a (long)nanoseconds value
 */
inline long seconds_to_nanoseconds(time_t seconds) {
	/* FIXME: is it safe to perform arithmetic operations on a (time_t) in kernel space? */
	return seconds * NANOSECONDS_PER_SECOND ;
}

/* @timespec_first_is_later
 * Check if the first (struct timespec) is a later time than the second (struct timespec)
 *
 * Precondition: @first and @second are valid (struct timespec) objects initialized via
 * 	calls to getnstimeofday() with the address of the the (struct timespec) as the argument
 *
 * Postcondition: This function returns a nonzero value if the time contained
 * 	in @first is a later time than the time contained in @second. If this
 * 	predicate is false, this function returns zero
 */
inline int timespec_first_is_later(struct timespec first, struct timespec second) {
	/* First, check if the first value's tv_secs field is greater. If it is, we
	 * know the @first is the later time of the two
	 */
	if (first.tv_sec > second.tv_sec) {
		return 1 ;
	}
	else
	/* If the above predicate was false, it is possible that the tv_secs fields
	 * of @first and @second are equal, and we can use the tv_nsecs field as
	 * a tiebeaker.
	 */
	if (first.tv_sec == second.tv_sec) {
		if (first.tv_nsec > second.tv_nsec) {
			return 1 ;
		}
	}
	/* If none of the return statements were executed above and control flow has
	 * reached this point, we can be certain that the first time is _not_
	 * greater than the second, and we return zero.
	 */
	return 0 ;
}

/* @timespec_to_nanoseconds
 * Convert a (struct timespec) to its equivalent in nanoseconds, represented as a (long) type
 *
 * Precondition: @timespec is a valid (struct timespec) object initialized via
 * 	call to getnstimeofday() with the address of the the (struct timespec) as the argument
 *
 * Postcondition: The function returns a (long) value representing, in nanoseconds, the value
 * 	stored in (struct timespec)@timespec
 */
inline long timespec_to_nanoseconds(struct timespec timespec) {
	/* Take the sum of both fields in (struct timespec)args represented as nanoseconds */
	return seconds_to_nanoseconds(timespec.tv_sec) + timespec.tv_nsec ;
}

/* @timespec_calculate_delta
 * Calculate the elapsed time between two valid struct timespec objects
 *
 * Precondition: @first and @second are valid (struct timespec) objects initialized
 * 	via calls to getnstimeofday() with the address of the the (struct timespec) as the argument
 *
 * Postconditon: The function returns a (long) value representing the time elapsed between
 * 	the instant represented in (struct timespec)@first and (struct timespec)@second.
 * 	Notably, this value can be negative, which implies that the first time is actually
 * 	later than the second time
 */
inline long timespec_calculate_delta(struct timespec first, struct timespec second) {
	long nanoseconds_first, nanoseconds_second ;

	nanoseconds_first = timespec_to_nanoseconds(first) ;
	nanoseconds_second = timespec_to_nanoseconds(second) ;

	/* Simply return the difference between the second and first time values */
	return nanoseconds_second - nanoseconds_first ;
}

/* @gettime_thread
 * Condinuously validate functionality of getnstime() until asked to stop
 *
 * Precondition: 
 */
static int gettime_thread(void *arg)
{
	int cpu = smp_processor_id() ;
	struct timespec timespec_first, timespec_second ;
	int we_have_not_yet_seen_time_go_backwards = 1 ;
	struct gettime_thread_data * thread_data = (struct gettime_thread_data *)arg ;

	/* Validate that the caller knows which cpu this thread is running on */
	WARN_ON(cpu != thread_data->cpu) ;
	/* Alright, we are good to go. Tell the caller we have started */
	thread_data->has_started = 1 ;

	printk(KERN_INFO "### [gettimed/%d] thread begins execution\n", cpu) ;

do_test:

	/* Capture the timestamps of two moments, one right after the other */
	getnstimeofday(&timespec_first) ;
	getnstimeofday(&timespec_second) ;

	/* If getnstimeofday() is working correctly, the second moment
	 * is guarenteed to be later than the first moment due to
	 * the above control flow.
	 */

	/* But, if the first moment is later than the second,
	 * the function does not satisfy it's requirements and the test fails
	 */
	if (timespec_first_is_later(timespec_first, timespec_second)
			&& we_have_not_yet_seen_time_go_backwards) {
		printk(KERN_INFO "test getnstimeofday() FAILED: time appears to flow "
				"in reverse! (delta value: %ld ns) \n", 
			timespec_calculate_delta(timespec_first, timespec_second)) ;

		/* For the first time, we have seen time move in reverse. The test will fail. */
		we_have_not_yet_seen_time_go_backwards = 0 ;
	}
	/* The condition for test failure is the the presence of the majoirity of the above
	 * test string in /var/log/messages following the insertion of this module
	 */

	/* Take a little break and let some other tasks have a go at our cpu */
	schedule_timeout_interruptible(msecs_to_jiffies(
			GETTIME_THREAD_INTERRUPTIBLE_SLEEP_MILLISECONDS)) ;

	/* This thread repeats the above behavior until it is politely asked to stop */
	if (!kthread_should_stop()) goto do_test ;

	printk(KERN_INFO "### [gettimed/%d] thread is terminating\n", cpu) ;

	return 0;
}

static int __init gettime_test(void)
{        
	int cpu = -1 ;
	size_t cpu_count = num_online_cpus() ;
	struct task_struct *gettime_thread_array[cpu_count] ;
	struct gettime_thread_data thread_data = (struct gettime_thread_data){.cpu = cpu, .has_started = 0 } ;

	BE_VERBOSE ? printk(KERN_INFO "### begin gettime module initialization\n") : (void)0 ;
	
	/* Zero the thread array to ensure sanity/clean out the garbage values */
	memset(gettime_thread_array, 0, sizeof(struct task_struct *) * cpu_count) ;

	for_each_online_cpu(cpu){
		BE_VERBOSE ? printk(KERN_INFO "### begin iteration for cpu%d \n", cpu) : (void)0 ;

		thread_data = (struct gettime_thread_data){ .cpu = cpu , .has_started = 0 } ;

		gettime_thread_array[cpu] = kthread_create_on_node(
				gettime_thread,
				&thread_data,
				cpu_to_node(cpu),
				"gettimed/%d", cpu) ;

		BE_VERBOSE ? printk(KERN_INFO "### created thread to be placed on cpu%d \n", cpu) : (void)0 ;

		if (IS_ERR(gettime_thread_array[cpu])) {
			/* If thread creation was unsuccessful, notify the user */
			printk(KERN_ERR "[gettimed/%d]: creating kthread failed!\n", cpu) ;
		} else {
			/* If thread creation was successful, ensure the thread
			 * is running on the correct cpu, and only then wake it up
			 */
			kthread_bind(gettime_thread_array[cpu], cpu) ;
			BE_VERBOSE ? printk(KERN_INFO "### thread bound to cpu%d \n", cpu) : (void)0 ;
			wake_up_process(gettime_thread_array[cpu]);
			BE_VERBOSE ? printk(KERN_INFO "### wake up on cpu%d returned to caller\n", cpu) : (void)0 ;
			while(!thread_data.has_started) {
				BE_VERBOSE ? printk(KERN_INFO "### waiting for OK from thred on cpu%d...\n", cpu) : (void)0 ;
				schedule_timeout_interruptible(
					msecs_to_jiffies(GETTIME_TEST_WAIT_MILLISECONDS)) ;
			}
			printk(KERN_INFO "### THREAD [%d] OK!\n", cpu) ;
		}
	} ;

	/* Let the threads run for a while before lining them up and executing them */
	schedule_timeout_interruptible(msecs_to_jiffies(
				GETTIME_TEST_INTERRUPTIBLE_SLEEP_MILLISECONDS)) ;

	/* Stop all remaining kthreads if they ever existed in the first place */
	for_each_online_cpu(cpu) {
		gettime_thread_array[cpu] ? kthread_stop(gettime_thread_array[cpu]) : (void)0 ;
	}

	printk(KERN_INFO "### gettime module init OK!\n") ;

	return 0 ;
}

static void __exit gettime_test_exit(void)
{
	printk(KERN_INFO "### gettime module exit OK!\n") ;
}

module_init(gettime_test) ;
module_exit(gettime_test_exit) ;

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Dong Zhu") ;
MODULE_DESCRIPTION("Getnstimeofday") ;
