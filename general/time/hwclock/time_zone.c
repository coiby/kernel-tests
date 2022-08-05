/*
 * Copyright (c) 2018 Red Hat, Inc. All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdio.h>
#include <sys/time.h>
#include <stdlib.h>
#include <errno.h>

int main(int argc, const char *argv[])
{      
	struct timeval tv;
	struct timezone tz;

	if (gettimeofday(NULL, &tz)) {
		perror("gettimeofday");
		return 1;
	}

	if (tz.tz_minuteswest == 0) {
		printf("ZONE: GMT\n");
	} else if (tz.tz_minuteswest > 0) {
		printf("ZONE: GMT - %d\n",tz.tz_minuteswest/60);
	} else
		printf("ZONE: GMT + %d\n",abs(tz.tz_minuteswest)/60);

	printf("system time zone : \n"
			"\t tz_minuteswest = %d\n"
			"\t tz_dsttime = %d\n",
			tz.tz_minuteswest,
			tz.tz_dsttime);

	return 0;
}
