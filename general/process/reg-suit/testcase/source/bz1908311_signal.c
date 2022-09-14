#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>

void sighandler(int sig) {
    printf("got signal %d\n", sig);
	exit(1);
}

int main () {
    setuid(0);
    signal(SIGSEGV, sighandler);
    while(1);
}
