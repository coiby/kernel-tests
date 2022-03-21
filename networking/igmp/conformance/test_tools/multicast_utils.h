/*
 * multicast_utils.h - common tools for kernel multicast tests
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

#ifndef __MULTICAST_UTILS_H__
#define __MULTICAST_UTILS_H__

#include <stdio.h>
#include <string.h>
#include <errno.h>

#include <netinet/in.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/select.h>

#include <signal.h>
#include <time.h>

#include <stdlib.h>
#include <unistd.h>

#define MESSAGE "Hello world!"

/* Verbose print */
#define printv(args...) \
	if (__verbosity > 0) \
	{ \
		printf(args); \
		fflush(stdout); \
	}

/** Structure that carries test parameters */
struct parameters
{
	struct in_addr multiaddr;
	struct in_addr interface;

	struct in6_addr multiaddr6;
	struct in6_addr interface6;

	int duration; /* seconds */
	short port;
	int protocol;
	unsigned int if_index;

	//RECEIVE
	struct in_addr sourceaddr;
	struct in6_addr sourceaddr6;

	//SEND
	double delay;
	int ttl;
	int loop;
	int hops;
	int pkts;
};

/** Initiailze socket for receiving multicast data */
int init_in_socket(struct in_addr multiaddr, short port);

int init_in_socket6(struct in6_addr multiaddr, short port);

/** Initialize socket for sending multicast data */
int init_out_socket();

int init_out_socket6();

/** Close a socket */
void free_socket(int sockfd);

/** Wait for data up to `duration' seconds */
int wait_for_data(int sockfd, int duration, int packet_limit);

/** Send data for specified amount of time */
int send_data(int sockfd, struct in_addr multiaddr, short port,
					int pkts, double delay);

int send_data6(int sockfd, struct in6_addr multiaddr, short port,
		int pkts, double delay);

int setup_sk4(struct parameters *params);

int send_sk4(int sockfd, struct parameters *params);

int setup_sk6(struct parameters *params);

int send_sk6(int sockfd, struct parameters *params);

/** Initialize parameters struct with default values. */
void default_parameters(struct parameters* params);
void usage(char *program_name, int retval);
/** Generic function for parsing arguments */
void parse_args(int argc, char** argv, struct parameters* args);

#endif
