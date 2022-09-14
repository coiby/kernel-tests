#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <linux/acct.h>
#include <sys/wait.h>

#define FNAME "./linux-acct"
#define ABORT(func)	perror(func);abort();

static long get_file_size(FILE *fp)
{
	long size = 0;

	if (fseek(fp, 0, SEEK_END)) {
		ABORT("fseek end");
	}

	size = ftell(fp);
	if (size < 0) {
		ABORT("ftell");
	}

	if (fseek(fp, 0, SEEK_SET)) {
		ABORT("fseek set");
	}

	return size;
}

static void read_acct(void)
{
	struct acct_v3 *rec = NULL;
	FILE *fp;
	int i, cnt;

	fp = fopen(FNAME, "rb");
	if (!fp) {
		ABORT("fopen rb");
	}

	cnt = get_file_size(fp) / sizeof(struct acct_v3);
	if (0 == cnt) {
		printf("%s is empty!\n", FNAME);
		system("ls -l " FNAME);
		return ;
	}

	rec = malloc(sizeof(struct acct_v3) * cnt);

	i = 0;
	while (fread(&rec[i], sizeof(struct acct_v3), 1, fp) > 0)
		i++;

	fclose(fp);

	for (i = 0; i < cnt; i++)
		printf("pid %d recoreded\n", rec[i].ac_pid);

	return ;
}

int
main(int argc, char *argv[])
{
	FILE *fp;
	pid_t pid;
	int i;

	fp = fopen(FNAME, "w");
	if (!fp) {
		ABORT("fopen w")
	} else 
		fclose(fp);

	if (acct(FNAME) < 0) {
		ABORT("acct on");
	}

	for (i = 0; i < 5; i ++) {
		if ((pid = fork()) < 0) {
			ABORT("fork");
		} else if(pid == 0) {
			char *argv[] = { "/bin/date", NULL };
			execve(argv[0], argv, NULL);
			ABORT("execve");
		} else {
			printf("pid %d forked\n", pid);
			usleep(100*1000);
		}
	}

	while (wait(NULL) > 0) ;

	if (acct(NULL) < 0) {
		ABORT("acct off");
	}

	read_acct();

	return 0;
}  
