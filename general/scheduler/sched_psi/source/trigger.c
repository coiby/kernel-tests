#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <poll.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char** argv)
{
    char * trig;
    if (argc < 2){
        printf("usage: %s <trigger-path> [some|full $stall-time $window]\n", argv[0]);
        exit(1);
    }
    else if(argc<3)
    {
        trig = "some 150000 1000000";
    }
    else{
        trig = argv[2];
    }
    char * trig_path = argv[1];

    struct pollfd fds;
    int n;
    fds.fd = open(trig_path, O_RDWR | O_NONBLOCK);
	if (fds.fd < 0) {
		printf("%s open error: %s\n",trig_path,
			strerror(errno));
		return 1;
	}
	fds.events = POLLPRI;

	if (write(fds.fd, trig, strlen(trig) + 1) < 0) {
		printf("%s write error: %s\n",trig_path,
			strerror(errno));
		return 1;
	}

	printf("waiting for events...\n");
	while (1) {
		n = poll(&fds, 1, -1);
		if (n < 0) {
			printf("poll error: %s\n", strerror(errno));
			return 1;
		}
		if (fds.revents & POLLERR) {
			printf("got POLLERR, event source is gone\n");
			return 0;
		}
		if (fds.revents & POLLPRI) {
			printf("event triggered!\n");
            exit(0);
		} else {
			printf("unknown event received: 0x%x\n", fds.revents);
			return 1;
		}
	}
    return 0;
}
