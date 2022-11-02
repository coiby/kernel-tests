#include <stdio.h>
#include <string.h>
#include <stdlib.h>


int main(int argc,char** argv)
{
        char path[256];
        snprintf(path, sizeof(path), "/sys/devices/system/node/node0/cpulist");
        FILE *rd = fopen(path, "r");
        int rc = fseek(rd, 0, SEEK_END);
        long fsize = ftell(rd);
	printf("fsize = %ld\n",fsize);

        // If fsize is zero, the test has failed
        if (fsize == 0) {
            return 1;
        } else {
            return 0;
        }
}
