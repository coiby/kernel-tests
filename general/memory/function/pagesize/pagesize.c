#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

/*
 * Get expected page size for booted architecture from user space.
 *
 * This was originally intended to verify the page size of the arm64-64k variant, but can also be
 * used to confirm the page size on other architectures.
 *
 * See 'man 2 uname' and coreutils source for use of struct utsname
 * https://github.com/coreutils/coreutils/blob/master/src/uname.c
 *
 * Alternatively get the current configuration directly from the shell:
 *	$ getconf PAGESIZE
 */

int main(void)
{
	long page_sz;
	struct utsname buf;

	errno = 0;

	page_sz = sysconf(_SC_PAGESIZE);
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
	printf("Operating system version: %s\n", buf.version);
	printf("Page size is: %ld\n", page_sz);

	// strcmp returns 0 if a match is found
	if (!strcmp("aarch64", buf.machine)) {
		// arm64-64k variant
		if (strstr(buf.release, "+64k")) {
			assert(page_sz == 65536);
		// all RHEL 8 arm64 releases
		} else if (strstr(buf.release, "el8")) {
			assert(page_sz == 65536);
		// default page size
		} else {
			assert(page_sz == 4096);
		}
	}

	// confirm page size of any future variants
	if (!strcmp("ppc64le", buf.machine)) {
		assert(page_sz == 65536 || page_sz == 4096);
	}

	if (!strcmp("s390x", buf.machine)) {
		assert(page_sz == 4096);
	}

	if (!strcmp("x86_64", buf.machine)) {
		assert(page_sz == 4096);
	}

	return 0;
}
