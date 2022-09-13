#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>

int main(int argc, char *argv[])
{
	int fd;
	int nr_file;
	int n;
	char s[1024];

	if (argc < 2) {
		fprintf(stderr, "Usage: %s <number of open file>\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	nr_file = atoi(argv[1]);	
	n = nr_file;
	while (n--) {
		sprintf(s, "/tmp/bz719495-%d", n);
		fd = open(s, O_CREAT);
		if (fd == -1)
			perror("open");
	}
	n = nr_file;
	while (n--) {
		sprintf(s, "/tmp/bz719495-%d", n);
		unlink(s);		
	}
	return 0;
}
