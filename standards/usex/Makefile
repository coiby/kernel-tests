# usex -- Author: David Anderson <anderson@redhat.com>

COMMON_HFILES=defs.h

COMMON_CFILES=usex.c io_test.c time_mgr.c xfer_mgr.c \
       utils.c float.c dry.c shell_mgr.c bin_mgr.c vmem.c debug.c \
       mk_target_id.c window_common.c window_manager.c \
       dhrystone.c whetstone.c

WIN_MGR_CFILES=curses_mgr.c gtk_mgr.c

CURSES_OFILES=build.o usex.o io_test.o time_mgr.o xfer_mgr.o \
       utils.o float.o dry.o shell_mgr.o bin_mgr.o vmem.o \
       debug.o window_common_curses.o window_manager_curses.o \
       dhrystone.o whetstone.o

GTK_OFILES=build.o usex.o io_test.o time_mgr.o xfer_mgr.o \
       utils.o float.o dry.o shell_mgr.o bin_mgr.o vmem.o \
       debug.o window_common_gtk.o window_manager_gtk.o \
       dhrystone.o whetstone.o

# for clean target:
OFILES = $(CURSES_OFILES) $(GTK_OFILES)

GTK_MGR_HFILES=gtk_mgr.h

FILES= $(COMMON_HFILES) $(COMMON_CFILES) $(WIN_MGR_CFILES) $(GTK_MGR_HFILES) \
       Makefile COPYING legalcode.txt

WARNINGS=-Wall
#WARNINGS=-Wall -Wstrict-prototypes -Wmissing-prototypes
#WARNING_ERROR=-Werror

INSTALLDIR=${DESTDIR}/usr/bin

# To add additional macro definitions, define this here or on the make command
# line:
CDEFS=

# To build usex or gnusex statically-linked, uncomment this LDFLAGS line:
# LDFLAGS=-static

all:
	@make --no-print-directory curses
# until usex ported to gtk2
	@if which gtk-config >/dev/null 2>&1; then \
	  echo;  \
	  make --no-print-directory gtk; \
	else \
	  echo -e "\nCan't find gtk-config -- skipping build of gnusex.  (requires gtk+ and gtk+-devel)"; \
	fi

curses:
	@make --no-print-directory usex DISPLAY=CURSES \
	CFLAGS="-c -g -D_CURSES_ $(CDEFS)"  \
	LIBS="-lncurses -lm -pthread"

gtk:
	@make --no-print-directory gnusex DISPLAY=GTK \
	CFLAGS="-c -g -D_GTK_  $(CDEFS) -I/usr/lib/glib/include `gtk-config --cflags`" \
	LIBS="-lm `gtk-config --cflags` `gtk-config --libs` -pthread"

usex: $(CURSES_OFILES)
	cc -o usex $(LDFLAGS) -g $(CURSES_OFILES) $(LIBS)

gnusex: $(GTK_OFILES) 
	cc -o gnusex $(LDFLAGS) -g $(GTK_OFILES) $(LIBS)

window_manager_curses.o: window_manager.c $(WIN_MGR_CFILES) $(COMMON_HFILES) 
	cc $(CFLAGS) window_manager.c -o window_manager_curses.o $(WARNINGS) $(WARNING_ERROR) 

window_manager_gtk.o: window_manager.c $(WIN_MGR_CFILES) $(COMMON_HFILES) $(GTK_MGR_HFILES)
	cc $(CFLAGS) window_manager.c -o window_manager_gtk.o $(WARNINGS) 

window_common_curses.o: window_common.c $(COMMON_HFILES)
	cc $(CFLAGS) window_common.c -o window_common_curses.o $(WARNINGS) $(WARNING_ERROR) 

window_common_gtk.o: window_common.c $(COMMON_HFILES) $(GTK_MGR_HFILES)
	cc $(CFLAGS) window_common.c -o window_common_gtk.o $(WARNINGS) 

usex.o: usex.c $(COMMON_HFILES)
	cc $(CFLAGS) usex.c $(WARNINGS) $(WARNING_ERROR)

utils.o: utils.c $(COMMON_HFILES)
	cc $(CFLAGS) utils.c $(WARNINGS) $(WARNING_ERROR)

time_mgr.o: time_mgr.c $(COMMON_HFILES)
	cc $(CFLAGS) time_mgr.c $(WARNINGS) $(WARNING_ERROR)

xfer_mgr.o: xfer_mgr.c $(COMMON_HFILES)
	cc $(CFLAGS) xfer_mgr.c $(WARNINGS) $(WARNING_ERROR) 

shell_mgr.o: shell_mgr.c $(COMMON_HFILES)
	cc $(CFLAGS) shell_mgr.c $(WARNINGS) $(WARNING_ERROR) 

bin_mgr.o: bin_mgr.c $(COMMON_HFILES)
	cc $(CFLAGS) bin_mgr.c $(WARNINGS) $(WARNING_ERROR)

io_test.o: io_test.c $(COMMON_HFILES)
	cc $(CFLAGS) io_test.c $(WARNINGS) $(WARNING_ERROR)

float.o: float.c $(COMMON_HFILES)
	cc $(CFLAGS) float.c $(WARNINGS) $(WARNING_ERROR)

dry.o: dry.c $(COMMON_HFILES)
	cc $(CFLAGS) dry.c $(WARNINGS) $(WARNING_ERROR)

vmem.o: vmem.c $(COMMON_HFILES)
	cc $(CFLAGS) vmem.c $(WARNINGS) $(WARNING_ERROR) 

debug.o: debug.c $(COMMON_HFILES)
	cc $(CFLAGS) debug.c $(WARNINGS) $(WARNING_ERROR)

dhrystone.o: dhrystone.c $(COMMON_HFILES)
	cc -g -c -DUSEX dhrystone.c 

whetstone.o: whetstone.c $(COMMON_HFILES)
	cc -g -c -DUSEX whetstone.c 

build.o: always_build
	@/bin/echo -n "char *build_date = \"" > build.c
	@/bin/echo "build date: `date`\";" >> build.c
	@/bin/echo -n "char *build_machine = \"" >> build.c
	@/bin/echo "build machine: `uname -a`\";" >> build.c
	@/bin/echo -n "char *build_id = \"" >> build.c
	@/bin/echo "build id: `id`\";" >> build.c
	@/bin/echo -n "char *build_sum = \"" >> build.c
	@/bin/echo "build sum: `/usr/bin/make -s -f Makefile sum`\";" >> build.c
	@cc -o mk_target_id mk_target_id.c $(WARNINGS) $(WARNING_ERROR)
	@./mk_target_id >> build.c
	@cc $(CFLAGS) build.c
	@rm -f build.c mk_target_id

always_build:
	@:

sum:
	cat `/usr/bin/make -s -f Makefile files` | sum -r | awk '{print $$1}'

files:
	@echo $(FILES)


name:	
	@echo usex

CSDB=.csdb
c:
	ctags $(COMMON_HFILES) $(COMMON_CFILES) $(WIN_MGR_CFILES) 
	mkdir -p $(CSDB)
	cscope -q -f $(CSDB)/cscope.out

install:
	@if [ "`id --user`" != "0" ] && [ -z "${DESTDIR}" ]; then \
		echo "make install: must be super-user"; exit 1; fi
	/usr/bin/install usex ${INSTALLDIR}
	if [ -f gnusex ]; then /usr/bin/install gnusex ${INSTALLDIR}; fi
	
tar:
	@tar cvzmf usex.tar.gz $(FILES)
	@ls -l usex.tar.gz

tard:
	@rm -f usex-`./usex -v | awk '{print $$6}'`.tar.gz
	@rm -rf usex-`./usex -v | awk '{print $$6}'`
	@mkdir usex-`./usex -v | awk '{print $$6}'`
	@cp ${FILES}  usex-`./usex -v | awk '{print $$6}'`
	@tar cvzmf usex-`./usex -v | awk '{print $$6}'`.tar.gz \
		usex-`./usex -v | awk '{print $$6}'`
	@ls -l usex-`./usex -v | awk '{print $$6}'`.tar.gz

release:
	@if [ "`id --user`" != "0" ]; then \
		echo "make release: must be super-user"; exit 1; fi
#	make all
	@make --no-print-directory tard
	@cp usex-`./usex -v | awk '{print $$6}'`.tar.gz /root/rpmbuild/SOURCES
	@rm -rf usex-`./usex -v | awk '{print $$6}'`
	@./usex --spec 2> usex.spec

	@if [ -s usex.spec ]; then \
	  rm -rf ./RPMBUILD; \
	  mkdir -p ./RPMBUILD/SOURCES ./RPMBUILD/SPECS ./RPMBUILD/SRPMS; \
	  cp usex-`./usex -v | awk '{print $$6}'`.tar.gz ./RPMBUILD/SOURCES; \
	  cp usex.spec ./RPMBUILD/SPECS; \
	  rpmbuild --define "_sourcedir ./RPMBUILD/SOURCES" \
	    --define "_srcrpmdir ./RPMBUILD/SRPMS" \
	    --define "_specdir ./RPMBUILD/SPECS" \
	    --nodeps -bs ./RPMBUILD/SPECS/usex.spec > /dev/null; \
	   mv ./RPMBUILD/SRPMS/usex-`./usex -v | awk '{print $$6}'`.src.rpm . ; \
	   rm -rf ./RPMBUILD; \
	   ls -l usex-`./usex -v | awk '{print $$6}'`.src.rpm; \
	fi

clean:
	rm -rf usex gnusex $(OFILES) mk_target_id $(CSDB)

