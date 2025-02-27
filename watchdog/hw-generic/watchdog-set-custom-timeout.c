// SPDX-License-Identifier: GPL-2.0
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/watchdog.h>
#include <sys/ioctl.h>

#define CUSTOM_TIMEOUT_S 30

int main(void)
{
	int fd = open("/dev/watchdog", O_WRONLY);
	int timeout;
	int ret = 0;
	if (fd == -1) {
		perror("watchdog");
		exit(EXIT_FAILURE);
	}
	ioctl(fd, WDIOC_GETTIMEOUT, &timeout);
	printf("Original timeout was %d seconds.\n", timeout);
	timeout = CUSTOM_TIMEOUT_S;
	ret = ioctl(fd, WDIOC_SETTIMEOUT, &timeout);
	if (ret == -1) {
		perror("WDIOC_SETTIMEOUT");
		close(fd);
		exit(EXIT_FAILURE);
	}
	ioctl(fd, WDIOC_GETTIMEOUT, &timeout);
	printf("Timeout is now %d seconds.\n", timeout);
	close(fd);
	return ret;
}
