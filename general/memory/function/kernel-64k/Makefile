.POSIX:

CC      = gcc
CFLAGS  = -Wall -Wextra -Werror -pedantic -O2 -g -std=gnu11 -D_FORTIFY_SOURCE=2

BINARIES := kernel-64k

.PHONY: run build clean

run: build
	./runtest.sh

build: $(BINARIES)
	test -x runtest.sh || chmod a+x runtest.sh

clean:
	rm -f $(BINARIES) a.out *.o vgore.* core
