/*
 * Copyright (c) 2019 Red Hat, Inc. All rights reserved.
 *
 * This copyrighted material is made available to anyone wishing
 * to use, modify, copy, or redistribute it subject to the terms
 * and conditions of the GNU General Public License version 2.
 *
 * This program is distributed in the hope that it will be
 * useful, but WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 * PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the Free
 * Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

#define _GNU_SOURCE
#include <linux/ip.h>
#include <arpa/inet.h>
#include <errno.h>
#include <error.h>
#include <netinet/udp.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef ETH_MAX_MTU
#define ETH_MAX_MTU	0xFFFFU
#endif

#define NUM_PKT		100

static bool		cfg_do_ipv4;
static bool		cfg_do_ipv6;

static char buf[NUM_PKT][ETH_MAX_MTU];
static char rbuf[ETH_MAX_MTU];

const struct in6_addr addr6 = IN6ADDR_LOOPBACK_INIT;
const struct in_addr addr4 = { .s_addr = __constant_htonl(INADDR_LOOPBACK + 2) };

static unsigned short	cfg_port = 9000;

struct testcase {
	int step;
	int total;
};

struct testcase testcases[] = {
	{
		.step = 1,
		.total = ETH_MAX_MTU - 20 - 8,
	},
	{
		.step = 3,
		.total = 30000,
	},
	{
		.step = 1024,
		.total = 10240,
	},
	{
		.step = 6000,
		.total = 60000,
	},
	{
		/* EOL */
	},
};


static int fill_buffer(int fdt, struct sockaddr *addr, socklen_t alen, int step, int total)
{
	int on = 1, done = 0, ret = 0;
	char * p = (char *)buf;

	if (setsockopt(fdt, IPPROTO_UDP, UDP_CORK, &on, sizeof(int))) {
		perror ("setsockopt UDP_CORK");
		exit (-1);
	}

	while (done < total) {
		ret = sendto(fdt, p + done, step, 0, addr, alen);
		if (ret == -1)
			error(1, errno, "sendto");
		if (ret != step)
			error(1, errno, "sendto: %uB != %uB\n", ret, step);

		done += ret;
	}
	return done;
}

static int send_out(int fdt, struct sockaddr *addr, socklen_t alen, int step)
{
	int off = 0, ret = 0;
	if (setsockopt(fdt, IPPROTO_UDP, UDP_CORK, &off, sizeof(int))) {
		perror ("setsockopt UDP_CORK");
		exit (-1);
	}
	ret = sendto(fdt, "XXXX", 0, 0, addr, alen);
	return ret;
}


static char sanitized_char(char val)
{
	return (val >= 'a' && val <= 'z') ? val : '.';
}

static void do_verify_udp(const char *data, int len)
{
	char cur = data[0];
	int i;

	/* verify contents */
	if (cur < 'a' || cur > 'z')
		error(1, 0, "data initial byte out of range");

	for (i = 1; i < len; i++) {
		if (cur == 'z')
			cur = 'a';
		else
			cur++;

		if (data[i] != cur)
			error(1, 0, "data[%d]: len %d, %c(%hhu) != %c(%hhu)\n",
			      i, len,
			      sanitized_char(data[i]), data[i],
			      sanitized_char(cur), cur);
	}
}

static void run_one(struct testcase *test, int fdt, int fdr, struct sockaddr *addr, socklen_t alen)
{
	int ret = 0;
	printf("\nsetting: step=%d, total=%d\n", test->step, test->total);
	ret = fill_buffer(fdt, addr, alen, test->step, test->total);
	if (ret != test->total) {
		error(1, errno, "FAIL: fill_buffer\n");
	}
	ret = recv(fdr, rbuf, ETH_MAX_MTU, MSG_TRUNC);
	if (ret < 0 && errno == EAGAIN) {
		printf("UDP_CORK OK\n");
	}
	else if (ret > 0) {
		error(1, errno, "FAIL: shouldn't recv packet, ret=%d\n", ret);
	}
	else
		error(1, errno, "recv after fill_buffer: ");

	ret = send_out(fdt, addr, alen, test->step);
	ret = recv(fdr, rbuf, ETH_MAX_MTU, MSG_TRUNC);
	if (ret == test->total) {
		printf("UNCORK OK\n");
		do_verify_udp(rbuf, test->total);
	}
	else
		error(1, errno, "FAIL: %d byte received, should be %d\n", ret, test->total);

//	printf("rbuf= %s\n", rbuf);


	//cleanup
	ret = recv(fdr, rbuf, ETH_MAX_MTU, 0);
	if (ret != 0)
		error(1, errno, "should recv 0");

}

static void run_all(int fdt, int fdr, struct sockaddr *addr, socklen_t alen)
{
	struct testcase *test;
	for (test = testcases; test->step; test++) {
			run_one(test, fdt, fdr, addr, alen);
	}
}

static void run_test(struct sockaddr *addr, socklen_t alen)
{
	struct timeval tv = { .tv_usec = 100 * 1000 };
	int fdr, fdt;

	fdr = socket(addr->sa_family, SOCK_DGRAM, 0);
	if (fdr == -1)
		error(1, errno, "socket r");

	if (bind(fdr, addr, alen))
		error(1, errno, "bind");

	/* Have tests fail quickly instead of hang */
	if (setsockopt(fdr, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)))
		error(1, errno, "setsockopt rcv timeout");

	fdt = socket(addr->sa_family, SOCK_DGRAM, 0);
	if (fdt == -1)
		error(1, errno, "socket t");

	run_all(fdt, fdr, addr, alen);

	if (close(fdt))
		error(1, errno, "close t");
	if (close(fdr))
		error(1, errno, "close r");
}

static void run_test_v4(void)
{
	struct sockaddr_in addr = {0};

	addr.sin_family = AF_INET;
	addr.sin_port = htons(cfg_port);
	addr.sin_addr = addr4;

	run_test((void *)&addr, sizeof(addr));
}

static void run_test_v6(void)
{
	struct sockaddr_in6 addr = {0};

	addr.sin6_family = AF_INET6;
	addr.sin6_port = htons(cfg_port);
	addr.sin6_addr = addr6;

	run_test((void *)&addr, sizeof(addr));
}

static void parse_opts(int argc, char **argv)
{
	int c;

	while ((c = getopt(argc, argv, "46cCmst:")) != -1) {
		switch (c) {
		case '4':
			cfg_do_ipv4 = true;
			break;
		case '6':
			cfg_do_ipv6 = true;
			break;
		default:
			error(1, 0, "%s: parse error", argv[0]);
		}
	}
}
int main(int argc, char **argv)
{
	parse_opts(argc, argv);
	int i;

	for (i = 0; i < sizeof(buf[0]); i++)
		buf[0][i] = 'a' + (i % 26);
	for (i = 1; i < NUM_PKT; i++)
		memcpy(buf[i], buf[0], sizeof(buf[0]));

	if (cfg_do_ipv4)
		run_test_v4();
	if (cfg_do_ipv6)
		run_test_v6();

	return 0;
}
