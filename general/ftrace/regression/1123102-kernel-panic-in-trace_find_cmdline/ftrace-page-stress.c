#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <sys/mman.h>
#define _GNU_SOURCE
#include <fcntl.h>

#define RUN_TIME 120 /* seconds */

static char *map;

static void die(char *fmt, ...)
{
	char str[1024];
	va_list ap;

	va_start(ap, fmt);
	vsprintf(str, fmt, ap);
	va_end(ap);

	perror(str);
	exit(-1);
}


#define _STR(x) #x
#define STR(x) _STR(x)
#define MAX_PATH	1024

static const char *find_debugfs(void)
{
	static char debugfs[MAX_PATH+1];
	static int debugfs_found;
	char type[100];
	FILE *fp;

	if (debugfs_found)
		return debugfs;

	if ((fp = fopen("/proc/mounts","r")) == NULL)
		die("/proc/mounts/");

	while (fscanf(fp, "%*s %"
		      STR(MAX_PATH)
		      "s %99s %*s %*d %*d\n",
		      debugfs, type) == 2) {
		if (strcmp(type, "debugfs") == 0)
			break;
	}
	fclose(fp);

	if (strcmp(type, "debugfs") != 0)
		die("debugfs not mounted, please mount");

	debugfs_found = 1;

	return debugfs;
}

/* read a page and a half at a time */
#define TRACE_READ_SIZE		(1024 * 6)

#ifndef SPLICE_F_MOVE
#define SPLICE_F_MOVE		1
#endif

static int page_size;


static int read_trace(int fd)
{
	char buf[TRACE_READ_SIZE];
	int total = 0;
	int ret;

	do {
		ret = read(fd, buf, TRACE_READ_SIZE);
		total += ret;
	} while (ret);

	return total;
}

static int do_splice(int fd_in, int fd_out, int *brass)
{
	char buf[page_size];
	int total = 0;
	int ret;

	do {
		ret = splice(fd_in, NULL, brass[1], NULL, page_size, SPLICE_F_MOVE);
		if (ret > 0)
			ret = splice(brass[0], NULL, fd_out, NULL, ret, SPLICE_F_MOVE);
		total += ret;
	} while (ret);

	sleep(1);

	do {
		ret = read(fd_in, buf, page_size);
		total += ret;
	} while (ret > 0);

	return total;
}

static int read_all(const char *trace_file)
{
	int fd;
	int ret;

	fd = open(trace_file, O_RDONLY);
	if (fd < 0) {
		perror(trace_file);
		exit(-1);
	}
	ret = read_trace(fd);
	close(fd);
	return ret;
}

static int splice_all(const char *pipe_file)
{
	int brass[2];
	int null_fd;
	int fd;
	int ret;

	fd = open(pipe_file, O_RDONLY);
	if (fd < 0) {
		perror(pipe_file);
		exit(-1);
	}

	null_fd = open("/dev/null", O_WRONLY);
	if (null_fd < 0) {
		perror("/dev/null");
		exit(-1);
	}

	if (pipe(brass) < 0) {
		perror("pipe");
		exit(-1);
	}

	ret = do_splice(fd, null_fd, brass);

	close(brass[0]);
	close(brass[1]);
	close(fd);
	close(null_fd);
	return ret;
}

static int read_file(const char *file, const char *type, int (*func)(const char *))
{
	unsigned long long total = 0;
	int ret;

	ret = fork();
	if (ret < 0)
		die("forking");
	if (ret)
		return ret;

	/* child */
	while (!map[0]) {
		total += func(file);
	}
	printf("%s total of %lld\n", type, total);
	exit(0);
	return 0;
}
static int start_reader(const char *file)
{
	return read_file(file, "read", read_all);
}

static int start_splicer(const char *file)
{
	return read_file(file, "spliced", splice_all);
}

static char *append_file(const char *dir, const char *file)
{
	int len;
	char *str;

	len = strlen(dir) + strlen(file) + 2;
	str = malloc(len);
	if (!str)
		die("malloc");
	sprintf(str, "%s/%s", dir, file);
	return str;
}

static void write_file(const char *file, const char *val)
{
	int len = strlen(val);
	int ret;
	int fd;

	fd = open(file, O_WRONLY);
	if (fd < 0) {
		perror(file);
		exit(-1);
	}
	ret = write(fd, val, len);
	if (ret < len)
		die("could not write '%s' to '%s'", val, file);

	close(fd);
}

static void do_trace(const char *current_tracer, const char *tracing_on,
		     const char *events_enable, const char *trace_file,
		     int clear, int check)
{
	FILE *fp;
	char *line;
	size_t len;
	int cnt;
	int acceptable = 1000; /* expect a 1000 lines from tracing */
	int ret;

	write_file(tracing_on, "0");
	printf("trace a little\n");

	if (clear) {
		write_file(current_tracer, "nop");
		/* This just clears the trace */
		write_file(trace_file, "0");
	}

	/* turn off tracing */
	write_file(current_tracer, "function");
	write_file(events_enable, "1");
	write_file(tracing_on, "1");
	sleep(5);

	/* If !check, then keep tracing */
	if (!check)
		return;

	write_file(tracing_on, "0");
	write_file(events_enable, "0");
	printf("check trace\n");

	/* make sure there's content, and lots of it */
	fp = fopen(trace_file, "r");
	if (!fp) {
		perror(trace_file);
		exit(-1);
	}

	line = NULL;
	len = 0;
	do {
		ret = getline(&line, &len, fp);
		if (ret < 0)
			break;
		if (!len)
			len = strlen(line);

		if (line[0] == '#')
			continue;
		cnt++;
	} while (cnt < acceptable);

	if (cnt < acceptable) {
		printf("failed to trace properly\n");
		exit(-1);
	}
	fclose(fp);
}

int main (int argc, char **argv)
{
	const char *debugfs;
	char *tracing_dir;
	char *per_cpu_dir;
	char *trace_file;
	char *events_enable;
	char *current_tracer;
	char *tracing_on;
	char progress[] = "\\|/-";
	pid_t rpid;
	pid_t *spid;
	int cpus;
	int status;
	int len;
	int i;

	cpus = sysconf(_SC_NPROCESSORS_CONF);
	if (cpus < 0)
		die("cpus?");

	debugfs = find_debugfs();
	tracing_dir = append_file(debugfs, "tracing");
	events_enable = append_file(tracing_dir, "events/enable");
	per_cpu_dir = append_file(tracing_dir, "per_cpu/cpu0");
	trace_file = append_file(tracing_dir, "trace");
	current_tracer = append_file(tracing_dir, "current_tracer");
	tracing_on = append_file(tracing_dir, "tracing_on");

	do_trace(current_tracer, tracing_on, events_enable, trace_file, 1, 0);

	page_size = getpagesize();

	spid = malloc(sizeof(*spid) * cpus);
	if (!spid)
		die("malloc");

	map = mmap(NULL, page_size, PROT_READ|PROT_WRITE,
		   MAP_SHARED|MAP_ANONYMOUS, -1, 0);
	if (!map) {
		perror("mmap");
		exit(-1);
	}

	printf("reading files for %d seconds\n", RUN_TIME);
	rpid = start_reader(trace_file);
	len = strlen(per_cpu_dir);
	per_cpu_dir[len - 1] = '\0';

	for (i = 0; i < cpus; i++) {
		char pipe_file[MAX_PATH];

		snprintf(pipe_file, MAX_PATH, "%s%d/trace_pipe_raw", per_cpu_dir, i);
		spid[i] = start_splicer(pipe_file);
	}
	for (i = 0; i < RUN_TIME; i++) {
		printf("%8d %c\r", RUN_TIME - i, progress[i & 3]);
		fflush(stdout);
		sleep(1);
	}
	printf("            \r");
	map[0] = 1;

	for (i = 0; i < cpus + 1; i++) {
		waitpid(-1, &status, WNOHANG);
		//wait(&status);
		if (status != 0)
			die("child failed");
	}
	
	printf("finished\n");
	do_trace(current_tracer, tracing_on, events_enable, trace_file, 0, 1);
	printf("SUCCESS!\n");
	return 0;
}
