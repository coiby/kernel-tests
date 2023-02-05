/*
 * Copyright (c) 2017 Red Hat, Inc. All rights reserved.
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
 *
 * Author: Qiao Zhao <qzhao@redhat.com>
 */

#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

#define M_SIZE (1UL<<30)  // for 1GB

int main() {
    int i = 0;

    while (1) {
	void *mem = mmap(NULL, M_SIZE, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	memset(mem, 0, M_SIZE);
	printf("Alloc count: %d\n", ++i);
    }

    printf("Allocated %lu BYTES\n", i * M_SIZE);
    return 0;
}
