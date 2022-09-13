#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

char bss[1000*1000*1000];

int main() {

    int i = 0;
    char c = 0;

    printf("pid:    %d\n", getpid());
    printf("&main:  %016p\n", &main);
    printf("bss:    %016p\n", bss);
    for(i = 0; i < sizeof(bss); ++i) {

      c |= bss[i];

    }

    getc(stdin);
    return 0;
}
