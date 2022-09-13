#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHUNKS 32

int 
main(int argc, char *argv[])
{
	unsigned long mb;
	char *buf[CHUNKS];
	int i;

	if (argc < 2) {
		exit(1);
	}
	mb = strtoul(argv[1], NULL, 0);

	for (i = 0; i < CHUNKS; i++) {
		buf[i] = (char *)malloc(mb/CHUNKS * 1024L * 1024L);
		if (!buf[i]) {
			fprintf(stderr, "malloc failure\n");
			exit(1);
		}
	}

	for (i = 0; i < CHUNKS; i++) {
		memset(buf[i], 0, mb/CHUNKS * 1024L * 1024L);
	}


	exit(0);
}
