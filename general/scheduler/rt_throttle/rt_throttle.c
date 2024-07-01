 /* Copyright (C) 2024, Chunyu Hu <chuhu@redhat.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *
 *  2. Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation
 *     and/or other materials provided with the distribution.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 *  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 *  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 *  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS
 *  BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 *  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 *  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 *  BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 *  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 *  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 *  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <sched.h>
#include <time.h>
#include <signal.h>
#include <semaphore.h>
#include <string.h>
#include <fcntl.h>

#define TEST_DURATION 10 // duration of the test in seconds
#define RT_RUNTIME_FILE "/proc/sys/kernel/sched_rt_runtime_us"
#define RT_PERIOD_FILE "/proc/sys/kernel/sched_rt_period_us"
#define RT_RUNTIME_TEST 950000
#define RT_PERIOD_TEST 1000000
#define STARVE_THRESHOULD 2

volatile long shared_var;
sem_t sem1, sem2, sem_end1, sem_end2;
volatile int running = 1;
volatile unsigned long iterations;
volatile unsigned long succeeds, failures;
pthread_t child1_thread, child2_thread;
int rt_runtime_us, rt_period_us;

int read_rt_throttle_config(const char *f)
{
	int fd;
	char buffer[32];
	ssize_t bytes_read;
	int value;

	fd = open(f, O_RDONLY);
	if (fd == -1) {
		perror("Error opening file for reading");
		return -1;
	}

	bytes_read = read(fd, buffer, sizeof(buffer) - 1);
	if (bytes_read == -1) {
		perror("Error reading value from file");
		close(fd);
		return -1;
	}

	buffer[bytes_read] = '\0';
	value = atoi(buffer);

	close(fd);

	return value;
}

int write_rt_throttle_config(const char *f, int new_value)
{
	int fd;
	char buffer[32];
	ssize_t bytes_written;

	fd = open(f, O_WRONLY);
	if (fd == -1) {
		perror("Error opening file for writing");
		return -1;
	}

	snprintf(buffer, sizeof(buffer), "%d\n", new_value);

	bytes_written = write(fd, buffer, strlen(buffer));
	if (bytes_written == -1) {
		perror("Error writing value to file");
		close(fd);
		return -1;
	}

	close(fd);

	return 0;
}

void set_rt_scheduler(int priority)
{
	struct sched_param param;
	param.sched_priority = priority;
	if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &param) != 0) {
		perror("pthread_setschedparam");
		exit(EXIT_FAILURE);
	}
}

void bind_cpu(pthread_t thread, int cpu)
{
	cpu_set_t cpuset;
	CPU_ZERO(&cpuset);
	CPU_SET(cpu, &cpuset);
	if (pthread_setaffinity_np(thread, sizeof(cpu_set_t), &cpuset) != 0) {
		perror("pthread_setaffinity_np");
		pthread_exit(NULL);
	}
}

/* thread1 (NORMAL) waits for the value set to 1 from thread2 (FIFO),
 * this waiting makes sure SCHED_FIFO will run first, otherwise, if NORMAL
 * runs first and sets the var to end value (2) directly, wound not
 * trigger RT throttle.
 * And then sets the value to 2 to kick thread2 to end the loop.
 */
void wait_and_set(long check_val, long set_val, sem_t *end_sem)
{
	while (shared_var != check_val  && running);
	shared_var = set_val;
	sem_post(end_sem);
}

/* thread2 (FIFO) sets the value to 1, and wait for thread1 to
 * set it to 2, if RT throttle works, thread1 (NORMAL) will have
 * some cputime to run to set the shared var to 2.
 */
void set_and_wait(long check_val, long set_val, sem_t *end_sem)
{
	shared_var = set_val;
	while (shared_var != check_val && running);
	sem_post(end_sem);
}

void* child1_func(void* arg)
{
	struct sched_param param = {};
	if (pthread_setschedparam(pthread_self(), SCHED_OTHER, &param) != 0) {
		perror("pthread_setschedparam");
		exit(EXIT_FAILURE);
	}
	while (running) {
		sem_wait(&sem1);
		if (!running)
			break;
		wait_and_set(1, 2, &sem_end1);
	}
	printf("child1 SCHED_NORMAL exit\n");
	pthread_exit(NULL);
}

void* child2_func(void* arg)
{
	set_rt_scheduler(1);

	while (running) {
		sem_wait(&sem2);
		if (!running)
			break;
		set_and_wait( 2, 1, &sem_end2);
	}
	printf("child2 SCHED_FIFO exit\n");
	pthread_exit(NULL);
}

void timer_handler(int signum)
{
	running = 0;
	sem_post(&sem1);  // ensure both children and master can exit
	sem_post(&sem2);
	sem_post(&sem_end1);
	sem_post(&sem_end2);
	pthread_cancel(child1_thread);
	pthread_cancel(child2_thread);
}

static int timer_running = 0;
void set_timeout(int timeout)
{
	struct itimerspec timer_spec;
	timer_t timer_id;

	timer_spec.it_value.tv_sec = timeout;
	timer_spec.it_value.tv_nsec = 500000000;
	timer_spec.it_interval.tv_sec = 0;
	timer_spec.it_interval.tv_nsec = 0;

	if (timer_running || timer_create(CLOCK_REALTIME, NULL, &timer_id) == -1) {
		perror("timer_create");
		exit(EXIT_FAILURE);
	}
	timer_running = 1;
	if (timer_settime(timer_id, 0, &timer_spec, NULL) == -1) {
		perror("timer_settime");
		exit(EXIT_FAILURE);
	}
}

int check_starvation(struct timespec *start)
{
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	if ((now.tv_sec - start->tv_sec) >= STARVE_THRESHOULD) {
		failures++;
		printf("RT throttle timeout!!\n");
		return 1;
	} else {
		succeeds++;
		return 0;
	}
}

/* reset the bandwidth timer*/
void reset_rt_period()
{
	write_rt_throttle_config(RT_RUNTIME_FILE, -1);
	write_rt_throttle_config(RT_PERIOD_FILE, RT_PERIOD_TEST);
	write_rt_throttle_config(RT_RUNTIME_FILE, RT_RUNTIME_TEST);
}

int main()
{
	struct sigaction sa;
	struct timespec start = {0};

	if (sem_init(&sem1, 0, 0) == -1 || sem_init(&sem2, 0, 0) == -1 ||
			sem_init(&sem_end1, 0, 0) == -1 || sem_init(&sem_end2, 0, 0) == -1) {
		perror("sem_init");
		exit(EXIT_FAILURE);
	}

	if (pthread_create(&child1_thread, NULL, child1_func, NULL) != 0) {
		perror("pthread_create");
		exit(EXIT_FAILURE);
	}

	if (pthread_create(&child2_thread, NULL, child2_func, NULL) != 0) {
		perror("pthread_create");
		exit(EXIT_FAILURE);
	}

	// set up a timer to end the test after TEST_DURATION seconds
	sa.sa_flags = SA_SIGINFO;
	sa.sa_handler = timer_handler;
	sigemptyset(&sa.sa_mask);
	if (sigaction(SIGALRM, &sa, NULL) == -1) {
		perror("sigaction");
		exit(EXIT_FAILURE);
	}
	set_timeout(TEST_DURATION);
	set_rt_scheduler(sched_get_priority_max(SCHED_FIFO));
	bind_cpu(child1_thread, 0);
	bind_cpu(child2_thread, 0);

	rt_runtime_us = read_rt_throttle_config(RT_RUNTIME_FILE);
	rt_period_us = read_rt_throttle_config(RT_PERIOD_FILE);
	printf("Default sched_rt_runtime_us=%d, sched_rt_period_us=%d\n",
			rt_runtime_us, rt_period_us);

	reset_rt_period();

	rt_runtime_us = read_rt_throttle_config(RT_RUNTIME_FILE);
	rt_period_us = read_rt_throttle_config(RT_PERIOD_FILE);
	printf("Test sched_rt_runtime_us=%d, sched_rt_period_us=%d\n",
			rt_runtime_us, rt_period_us);

	// warm up first loop
	sem_post(&sem1); //wake up Child 1
	sem_post(&sem2); // wake up Child 2
	sem_wait(&sem_end1); // wait for Child 1
	sem_wait(&sem_end2); // wait for Child 2

	while (running) {
		printf("Start test cycle %lu\n", iterations+1);
		shared_var = 0;
		clock_gettime(CLOCK_MONOTONIC, &start);

		sem_post(&sem1);
		sem_post(&sem2);

		sem_wait(&sem_end1);
		sem_wait(&sem_end2);

		(void)check_starvation(&start);

		printf("iterations=%lu, succeeds=%lu, failures=%lu\n",
				iterations+1, succeeds, failures);

		if (!running)
			break;

		iterations++;
	}

	printf("%s: iterations=%lu, succeeds=%lu, failures=%lu\n",
			succeeds > 0? "PASS" : "FAIL", iterations+1, succeeds, failures);

	pthread_join(child1_thread, NULL);
	pthread_join(child2_thread, NULL);

	sem_destroy(&sem1);
	sem_destroy(&sem2);
	sem_destroy(&sem_end1);
	sem_destroy(&sem_end2);

	// restore to the default values
	write_rt_throttle_config(RT_RUNTIME_FILE, -1);
	write_rt_throttle_config(RT_PERIOD_FILE, rt_period_us);
	write_rt_throttle_config(RT_RUNTIME_FILE, rt_runtime_us);
	/* 10 loops succeeds 5 times, activities such as batch of irqs could
	 * increase the latency
	 */
	return !(succeeds > 5);
}

