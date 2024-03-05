#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stacklib.h>

void usage(void)
{
    printf("usage: stackman [overflow|underflow|scribbling]\n");
    exit(1);
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        usage();
    }
    if (!strcmp(argv[1], "overflow")) {
        overflow();
    } else if (!strcmp(argv[1], "underflow")) {
        underflow();
    } else if (!strcmp(argv[1], "scribbling")) {
        scribbling();
    } else {
        printf("Unknown testmode: %s\n", argv[1]);
    }
}
