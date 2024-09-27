#include <errno.h>
#include <error.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

int
main (void)
{
	char fname[] = "/mnt/testarea/test.XXXXXX";
	int fd = mkstemp (fname);

	if (fd == -1)
		error (1, errno, "mkstemp");
	
	size_t ps = sysconf (_SC_PAGESIZE);
	int e = posix_fallocate (fd, 0, ps);

	if (e != 0)
		error (1, e, "posix_fallocate");

	char *p = mmap (NULL, 2 * ps, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);

	if (p == NULL)
		error (1, errno, "mmap");

	e = posix_fallocate (fd, ps, ps);

	if (e != 0)
		error (1, e, "2nd posix_fallocate");

	if (p[ps] != '\0')
		error (1, 0, "accessed value wrong");

	p[ps + 16] = 'A';

	if (msync (p, 2 * ps, MS_SYNC) < 0)
		error (1, errno, "msync");

	off_t o = lseek (fd, ps, SEEK_SET);

	if (o == (off_t) -1)
		error (1, errno, "lseek");

	else if (o != ps)
		error (1, 0, "lseek %ld != %zd", (long) o, ps);

	char buf[32];
	ssize_t s = read (fd, buf, sizeof buf);

	if (s < 0)
		error (1, errno, "read");
	else if ((size_t) s != sizeof buf)
		error (1, 0, "read %zd != %zd", (size_t) s, sizeof buf);

	if (buf[16] != 'A')
		error (1, 0, "value read by read wrong");

	puts ("Pass");
	return 0;
}
