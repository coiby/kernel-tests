#include <stdio.h>
#include <sys/types.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdlib.h>
#include <asm/ldt.h>

/*
 * Description: Cover x86 ldt.c
 * Author: Chunyu Hu <chuhu@redhat.com>
 */

/*struct user_desc {
   unsigned int  entry_number;
   unsigned long base_addr;
   unsigned int  limit;
   unsigned int  seg_32bit:1;
   unsigned int  contents:2;
   unsigned int  read_exec_only:1;
   unsigned int  limit_in_pages:1;
   unsigned int  seg_not_present:1;
   unsigned int  useable:1;
}; */

int modify_ldt(int func, void *ptr, unsigned long bytecount);

void print_ldt(struct user_desc *ud, int size)
{
	int i = 0;
	if (ud) {
		for (i=0; i<size; i++) {
			printf("entry_number = %x\n", ud->entry_number);
			printf("base_addr    = %p\n", ud->base_addr);
			printf("limit        = %x\n", ud->limit);
			ud++;
		}
	}
}

int main()
{
	void *data = mmap(NULL, 128, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS, -1, 0);
	memset(data, 0, 128);
	struct user_desc ud = {
		.entry_number = 0,
		.base_addr =  (unsigned long)data,
		.limit = 16 * sizeof(long),
		.seg_32bit = 1,
		.contents = 1,
		.read_exec_only = 0,
		.limit_in_pages = 0,
		.seg_not_present = 0,
		.useable = 1,
	};
	struct user_desc ud_read[8200] = {
		[0] = {
			.entry_number = 0
		},
		[1] = {
			.entry_number = 1
		}
	};
	/*
	 * First loop is to isntall ldt
	 *
	 * */
	int ret = modify_ldt(1, &ud, sizeof(ud));
	if (ret) {
		perror("modify_ldt: write");
		printf("return = %d\n", ret);
		exit(1);
	}
	/*
	 * Second loop is to reintall ldt, when there is and old ldt
	 * */

	ret = modify_ldt(1, &ud, sizeof(ud));
	if (ret) {
		perror("modify_ldt: write");
		printf("return = %d\n", ret);
		exit(1);
	}
	/*
	 * A dummy read test, to trigger kernel read default ldt. It echo back
	 * the second param.
	 * */
	ret = modify_ldt(2, &ud, sizeof(ud));
	if (ret < 0) {
		perror("modify_ldt: read default");
		printf("(echo)return = %d\n", ret);
		exit(1);
	} else {
		printf("(echo)return = %d\n", ret);
	}

	/* Read a large size to go into the coner branch*/
	ret = modify_ldt(0, &ud_read, sizeof(ud)*2 + 8200);
	if (ret > 0) {
		printf("read %d\n", ret);
		print_ldt(&ud_read[0], 2);
	} else {
		perror("modify_ldt: read");
		printf("return = %d\n", ret);
	}

	/* In !oldmode, Read a large size to go into the coner branch*/
	ret = modify_ldt(0x11, &ud, sizeof(ud));
	if (ret) {
		perror("0x11 modify_ldt: write");
		printf("0x11 return = %d\n", ret);
		exit(1);
	} else {
		printf("0x11 write");
		printf("return = %d\n", ret);
	}

	if (fork() == 0) {
		memset(data, 'a', 16);
	} else {
		while(((char*)data)[0] == 0);
		puts(data);
	}
	return ret;
}
