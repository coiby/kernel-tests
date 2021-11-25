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

#include <sys/types.h>
#include <sys/socket.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <netinet/ip.h>
#include <netinet/ip6.h>
#include <linux/udp.h>

/*For udp_SEGMENT*/
#define CONST_MTU_TEST  1500
#define CONST_HDRLEN_V4     (sizeof(struct iphdr) + sizeof(struct udphdr))
#define CONST_HDRLEN_V6     (sizeof(struct ip6_hdr) + sizeof(struct udphdr))

#define CONST_MSS_V4        (CONST_MTU_TEST - CONST_HDRLEN_V4)
#define CONST_MSS_V6        (CONST_MTU_TEST - CONST_HDRLEN_V6)

int get_set_test(char * family)
{
	int on = 1;
	int off = 0;
	int reval = 0;
	int fd = 0;
	socklen_t optlen = sizeof(reval);
	if (strcmp (family, "ipv4") == 0)
		fd = socket(PF_INET, SOCK_DGRAM, 0);
	else if (strcmp (family, "ipv6") == 0)
		fd = socket(PF_INET6, SOCK_DGRAM, 0);

	else {
		dprintf(2, "family error\n");
		exit (-1);
	}
// UDP_GRO
	if (setsockopt(fd, IPPROTO_UDP, UDP_GRO, &on, sizeof(int))) {
		perror ("setsockopt UDP_GRO");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_GRO, &reval, &optlen)) {
		perror ("getsockopt UDP_GRO");
		exit (-1);
	}
	if (reval != on){
		dprintf(2, "UDP_GRO getsockopt fail");
		exit (-1);
	}
	if (setsockopt(fd, IPPROTO_UDP, UDP_GRO, &off, sizeof(int))) {
		perror ("setsockopt UDP_GRO");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_GRO, &reval, &optlen)) {
		perror ("getsockopt UDP_GRO");
		exit (-1);
	}
	if (reval != off){
		dprintf(2, "UDP_GRO getsockopt fail");
		exit (-1);
	}

// UDP_SEGMENT
	int domain = 0;
	int value = 0;
	getsockopt(fd, SOL_SOCKET, SO_DOMAIN, &domain, &optlen);
	if (domain == AF_INET)
		value = CONST_MSS_V4;
	else
		value = CONST_MSS_V6;

	if (setsockopt(fd, IPPROTO_UDP, UDP_SEGMENT, &value, sizeof(int))) {
		perror ("setsockopt UDP_SEGMENT");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_SEGMENT, &reval, &optlen)) {
		perror ("getsockopt UDP_SEGMENT");
		exit (-1);
	}
	if (reval != value){
		dprintf(2, "UDP_SEGMENT getsockopt fail");
		exit (-1);
	}
	if (setsockopt(fd, IPPROTO_UDP, UDP_SEGMENT, &off, sizeof(int))) {
		perror ("setsockopt UDP_SEGMENT");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_SEGMENT, &reval, &optlen)) {
		perror ("getsockopt UDP_SEGMENT");
		exit (-1);
	}
	if (reval != off){
		dprintf(2, "UDP_SEGMENT getsockopt fail");
		exit (-1);
	}
// UDP_CORK
	if (setsockopt(fd, IPPROTO_UDP, UDP_CORK, &on, sizeof(int))) {
		perror ("setsockopt UDP_CORK");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_CORK, &reval, &optlen)) {
		perror ("getsockopt UDP_CORK");
		exit (-1);
	}
	if (reval != on){
		dprintf(2, "UDP_CORK getsockopt fail");
		exit (-1);
	}
	if (setsockopt(fd, IPPROTO_UDP, UDP_CORK, &off, sizeof(int))) {
		perror ("setsockopt UDP_CORK");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_CORK, &reval, &optlen)) {
		perror ("getsockopt UDP_CORK");
		exit (-1);
	}
	if (reval != off){
		dprintf(2, "UDP_CORK getsockopt fail");
		exit (-1);
	}
// UDP_ENCAP
	value = UDP_ENCAP_L2TPINUDP;
	if (setsockopt(fd, IPPROTO_UDP, UDP_ENCAP, &value, sizeof(int))) {
		perror ("setsockopt UDP_ENCAP");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_ENCAP, &reval, &optlen)) {
		perror ("getsockopt UDP_ENCAP");
		exit (-1);
	}
	if (reval != UDP_ENCAP_L2TPINUDP){
		dprintf(2, "UDP_ENCAP getsockopt fail");
		exit (-1);
	}
	if (setsockopt(fd, IPPROTO_UDP, UDP_ENCAP, &off, sizeof(int))) {
		perror ("setsockopt UDP_ENCAP");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_ENCAP, &reval, &optlen)) {
		perror ("getsockopt UDP_ENCAP");
		exit (-1);
	}
	if (reval != off){
		dprintf(2, "UDP_ENCAP getsockopt fail");
		exit (-1);
	}
// UDP_NO_CHECK6_TX
	reval = 0;
	if (setsockopt(fd, IPPROTO_UDP, UDP_NO_CHECK6_TX, &on, sizeof(int))) {
		perror ("setsockopt UDP_NO_CHECK6_TX");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_NO_CHECK6_TX, &reval, &optlen)) {
		perror ("getsockopt UDP_NO_CHECK6_TX");
		exit (-1);
	}
	if (reval != on){
		dprintf(2, "UDP_NO_CHECK6_TX getsockopt fail");
		exit (-1);
	}
	if (setsockopt(fd, IPPROTO_UDP, UDP_NO_CHECK6_TX, &off, sizeof(int))) {
		perror ("setsockopt UDP_NO_CHECK6_TX");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_NO_CHECK6_TX, &reval, &optlen)) {
		perror ("getsockopt UDP_NO_CHECK6_TX");
		exit (-1);
	}
	if (reval != off){
		dprintf(2, "UDP_NO_CHECK6_TX getsockopt fail");
		exit (-1);
	}
// UDP_NO_CHECK6_RX
	reval = 0;
	if (setsockopt(fd, IPPROTO_UDP, UDP_NO_CHECK6_RX, &on, sizeof(int))) {
		perror ("setsockopt UDP_NO_CHECK6_RX");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_NO_CHECK6_RX, &reval, &optlen)) {
		perror ("getsockopt UDP_NO_CHECK6_RX");
		exit (-1);
	}
	if (reval != on){
		dprintf(2, "UDP_NO_CHECK6_RX getsockopt fail");
		exit (-1);
	}
	if (setsockopt(fd, IPPROTO_UDP, UDP_NO_CHECK6_RX, &off, sizeof(int))) {
		perror ("setsockopt UDP_NO_CHECK6_RX");
		exit (-1);
	}
	if (getsockopt(fd, IPPROTO_UDP, UDP_NO_CHECK6_RX, &reval, &optlen)) {
		perror ("getsockopt UDP_NO_CHECK6_RX");
		exit (-1);
	}
	if (reval != off){
		dprintf(2, "UDP_NO_CHECK6_RX getsockopt fail");
		exit (-1);
	}
	return 0;
}

void bz518034()
{
	int fd = socket(PF_INET, SOCK_DGRAM, 0);
	char buf[1024] = {0};
	struct sockaddr to = {
		.sa_family = AF_UNSPEC,
		.sa_data   = "TavisIsAwesome",
	};

	// Bug 518034 - kernel: udp socket NULL ptr dereference
	sendto(fd, buf, 1024, MSG_PROXY | MSG_MORE, &to, sizeof(to));
	sendto(fd, buf, 1024, 0, &to, sizeof(to));
}

int main(int argc, char **argv)
{
	bz518034();
	get_set_test("ipv4");
	get_set_test("ipv6");

	return 0;
}
