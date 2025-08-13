#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main (void) {
        int n = 0;
        char *p;

        while (1) {
                if ((p = malloc(1<<20)) == NULL) {
                        printf("malloc failure after %d MiB\n", n);
                        return 0;
                }
                memset (p, 0, (1<<20));
                n++;
                if (n % 100 == 0)
                        printf ("got %d MiB\n", n);
                if (n > 10000)
                        break;
        }
        if (n > 10000)
                printf("Didn't oom this time\n");
        printf ("got %d MiB\n", n);
}
