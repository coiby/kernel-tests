/*  Author: David Anderson <anderson@redhat.com> */

/*
 *  mk_target_id.c
 */

#include "defs.h"

int
main(int argc, char **argv)
{
	printf("char *build_target_id = \"%s USEX_VERSION %s\";\n",
		MACHINE_TYPE, USEX_VERSION);	

	exit(0);
}

