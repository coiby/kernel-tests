/*
 * recv_membership.c - Join multicast group and leave it
 *                     in the middle of communication
 *
 * Copyright (C) 2012 Red Hat Inc.
 *
 * Author: Radek Pazdera (rpazdera@redhat.com)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA.
 */


#include "multicast_utils.h"

int recv_group4(int snd_sk, struct parameters *params)
{
	int sockfd = init_in_socket(params->multiaddr, params->port);
	int num_recv = 0, num_snd;
	struct group_req greq;


	num_snd = send_sk4(snd_sk, params);
	num_recv = wait_for_data(sockfd, 0, num_snd);
	printf("packets_received_before_join=%d\n", num_recv);

	greq.gr_interface = params->if_index;
	greq.gr_group.ss_family = AF_INET;
	((struct sockaddr_in *)&greq.gr_group)->sin_addr = params->multiaddr;
	if (setsockopt(sockfd, IPPROTO_IP, MCAST_JOIN_GROUP,
			   &(greq), sizeof(greq)) < 0) {
		perror("setsockopt");
		return EXIT_FAILURE;
	}
	num_snd = send_sk4(snd_sk, params);
	num_recv = wait_for_data(sockfd, 0, num_snd);
	printf("packets_received=%d\n", num_recv);

	if (setsockopt(sockfd, IPPROTO_IP, MCAST_LEAVE_GROUP,
			   &(greq), sizeof(greq)) < 0) {
		perror("setsockopt");
		return EXIT_FAILURE;
	}

	num_snd = send_sk4(snd_sk, params);
	num_recv = wait_for_data(sockfd, 0, num_snd);
	printf("packets_received_after_leave=%d\n", num_recv);

	return 0;
}

int recv_group6(int snd_sk, struct parameters *params)
{
	int sockfd = init_in_socket6(params->multiaddr6, params->port);
	int num_recv = 0, num_snd = 0;
	struct group_req greq6;

	num_snd = send_sk6(snd_sk, params);
	num_recv = wait_for_data(sockfd, 0, num_snd);
	printf("packets_received_before_join=%d\n", num_recv);

	greq6.gr_interface = params->if_index;
	greq6.gr_group.ss_family = AF_INET6;
	((struct sockaddr_in6 *)&greq6.gr_group)->sin6_addr = params->multiaddr6;
	if((setsockopt(sockfd,IPPROTO_IPV6, MCAST_JOIN_GROUP,
					&greq6, sizeof(greq6))) < 0)
	{
		perror("setsockopt");
		return EXIT_FAILURE;
	}
	num_snd = send_sk6(snd_sk, params);
	num_recv = wait_for_data(sockfd, 0, num_snd);
	printf("packets_received=%d\n", num_recv);

	if((setsockopt(sockfd,IPPROTO_IPV6, MCAST_LEAVE_GROUP,
					&greq6, sizeof(greq6))) < 0)
	{
		perror("setsockopt");
		return EXIT_FAILURE;
	}
	num_snd = send_sk6(snd_sk, params);
	num_recv = wait_for_data(sockfd, 0, num_snd);
	printf("packets_received_after_leave=%d\n", num_recv);

	return 0;
}

int main(int argc, char** argv)
{
	struct parameters params;
	parse_args(argc, argv, &params);
	int ret = 0, snd_sk;

	if ( 4 == params.protocol )
	{
		snd_sk = setup_sk4(&params);
		ret = recv_group4(snd_sk, &params);
	}
	else
	{
		snd_sk = setup_sk6(&params);
		ret = recv_group6(snd_sk, &params);
	}

	return ret;
}
