#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

/*
 * Verify that a 4k kernel is not installed alongside the 64k kernel.
 *
 * Installing the operating system with a 64k kernel should not install the 4k
 * kernel. It is not recommended to move between 4k and 64k kernels without
 * reinstallation of the operating system. Additional packages should not bring
 * in the 4k kernel post installation.
 *
 * References:
 *   The Linux Programming Interface
 *   'man 2 uname' and coreutils source for use of struct utsname
 *     https://github.com/coreutils/coreutils/blob/master/src/uname.c
 */

int main(void)
{
	long page_sz;
	struct utsname buf;
	DIR *dirp;
	struct dirent *dp;
	regex_t regex;

	errno = 0;
	page_sz= sysconf(_SC_PAGESIZE);

	if (errno) {
		perror("sysconf _SC_PAGESIZE");
		return errno;
	}

	uname(&buf);
	if (errno) {
		perror("Unable to get system information from uname");
		return errno;
	}

	printf("Architecture is: %s\n", buf.machine);
	printf("Operating system release: %s\n", buf.release);
	printf("Page size is: %ld\n\n", page_sz);

	// This test should only be run on aarch64, but check anyway
	if (page_sz == 65536 && !strcmp("aarch64", buf.machine) && strstr(buf.release, "+64k")) {
		// Match kernel names that do NOT end with an extra suffix
		errno = regcomp(&regex, "^vmlinuz[-].*aarch64$", 0);
		if (errno) {
			perror("Regex failed to compile");
			return errno;
		}

		dirp = opendir("/boot");
		if (dirp == NULL) {
			perror("Unable to open /boot");
		}

		if (dirp) {
			while ((dp = readdir(dirp)) != NULL) {
				errno = regexec(&regex, dp->d_name, 0, NULL, 0);
				if (!errno) {
					printf("Fail: a non-64k kernel was found on /boot: %s\n", dp->d_name);
					exit(EXIT_FAILURE);
				}
			}
			closedir(dirp);
		}
		regfree(&regex);
	} else {
		printf("Fail: This test should only be run on aarch64 with a 64k kernel\n");
		exit(EXIT_FAILURE);
	}

	return 0;
}
