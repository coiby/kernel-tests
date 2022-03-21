#include <getopt.h>
#include <stdlib.h>
#include <unistd.h>
#include <net/if.h>
#include "multicast_utils.h"

int __verbosity = 0;
/** Initialize parameters struct with default values. */
void default_parameters(struct parameters* params)
{
	params->port = 0;
	memset(&params->multiaddr, 0, sizeof(struct in_addr));
	memset(&params->interface, 0, sizeof(struct in_addr));
	memset(&params->multiaddr6, 0, sizeof(struct in6_addr));
	memset(&params->interface6, 0, sizeof(struct in6_addr));
	params->protocol = 4;
	params->if_index = 0;
	//RECEIVE
	memset(&params->sourceaddr, 0, sizeof(struct in_addr));
	memset(&params->sourceaddr6, 0, sizeof(struct in6_addr));
	//SEND
	params->delay = 0.1;
	params->ttl = 1;
	params->loop = 1;
	params->hops = 1;
	params->pkts = 5;
}

void usage(char *program_name, int retval)
{
	printf("usage: %s\n", program_name);
	printf("       -h | --help                        print this\n");
	printf("       -v | --verbose                     print additional information during the runtime\n");
	printf("       -i | --interface a.b.c.d/aa:bb::cc           local interface ipv4 or ipv6 to use for communication\n");
	printf("       -c | --protocol x                  test protocol\n");
	printf("       -n | --if_index x                  interface name\n");

	printf("\n");

	printf("       -a | --multicast_address a.b.c.d/aa:bb::dd   multicast group address\n");
	//RECEIVE
	printf("       -s | --source_address a.b.c.d/aa:bb::cc      multicast source (for SSM)\n");
	printf("       -p | --port x                      port number\n");
	//SEND
	printf("\n");

	printf("       -t | --ttl x                       time to live for IP packet\n");
	printf("       -l | --loop x                      loopback multicast communication\n");
	printf("       -e | --hops x                      hops for ipv6\n");
	printf("       -f | --delay x                     delay between messages\n");

	exit(retval);
}

/** Generic function for parsing arguments */
void parse_args(int argc, char** argv, struct parameters* args)
{
	#define __send_opts "f:t:l:e:"
	#define __recv_opts "s:"
	char *src_addr = "::";

	char *if_addr = "::";
	char *group_addr = "::";
	static const char* opts = __send_opts __recv_opts "d:a:p:i:c:n:hv";


	static struct option long_options[] =
	{
		//SEND
		{"delay",               required_argument, NULL, 'f'},
		{"ttl",	                required_argument, NULL, 't'},
		{"hops",	            required_argument, NULL, 'e'},
		{"loop",                required_argument, NULL, 'l'},
		//RECEIVE
		{"source_address",      required_argument, NULL, 's'},
		{"multicast_address",   required_argument, NULL, 'a'},
		{"port",                required_argument, NULL, 'p'},
		{"protocol",            required_argument, NULL, 'c'},
		{"if_index",            required_argument, NULL, 'n'},
		{"interface",           required_argument, NULL, 'i'},
		{"help",                no_argument,       NULL, 'h'},
		{"verbose",             no_argument,       NULL, 'v'},
		{0,                    0,                 NULL,  0}
	};

	default_parameters(args);

	int opt;
	int option_index = 0;
	while((opt = getopt_long(argc, argv, opts, long_options,
						&option_index)) != -1) {
		switch (opt) {
		//SEND
		case 'f':
			args->delay = atof(optarg);
			break;
		case 't':
			args->ttl = atoi(optarg);
			break;
		case 'e':
			args->hops = atoi(optarg);
			break;
		case 'l':
			args->loop = atoi(optarg);
			break;
		//RECEIVE
		case 's':
			src_addr = optarg;
			break;
		case 'c':
			args->protocol = atoi(optarg);
			break;
		case 'n':
			args->if_index = if_nametoindex(optarg);
			break;
		case 'a':
			group_addr = optarg;
			break;
		case 'p':
			args->port = atoi(optarg);
			break;
		case 'i':
			if_addr = optarg;
			break;
		case 'h':
			usage(argv[0], EXIT_SUCCESS);
			break;
		case 'v':
			__verbosity = 1;
			break;
		default: /* '?' */
			fprintf(stderr, "%s: invalid options\n", argv[0]);
			usage(argv[0], EXIT_FAILURE);
		}
	}
	if ( 4 != args->protocol && 6 != args->protocol )
	{
		printf("protocol should be 4 or 6\n");
		usage(argv[0], EXIT_FAILURE);
	}
	if ( 4 == args->protocol )
	{
		if(0 == strcmp(group_addr, "::"))
		{
			group_addr = "0.0.0.0";
		}
		if( 0 == strcmp(if_addr, "::"))
		{
			if_addr = "0.0.0.0";
		}
		inet_pton(AF_INET, group_addr, &(args->multiaddr));
		inet_pton(AF_INET, if_addr, &(args->interface));
		//RECEIVE
		if( 0 == strcmp(src_addr, "::"))
		{
			src_addr = "0.0.0.0";
		}
		inet_pton(AF_INET, src_addr, &(args->sourceaddr));
	}
	else
	{
		inet_pton(AF_INET6, group_addr, &(args->multiaddr6));
		inet_pton(AF_INET6, if_addr, &(args->interface6));
		//RECEIVE
		inet_pton(AF_INET6, src_addr, &(args->sourceaddr6));
	}
}

/** Initiailze socket for receiving multicast data */
int init_in_socket(struct in_addr multiaddr, short port)
{
	int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
	if (sockfd < 0)	{
		perror("socket()");
		exit(EXIT_FAILURE);
	}

	struct sockaddr_in addr;
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr = multiaddr;
	memset(&(addr.sin_zero), 0, sizeof(addr.sin_zero));

	if (bind(sockfd, (struct sockaddr*) &addr, sizeof(addr)) < 0) {
		perror("bind()");
		exit(EXIT_FAILURE);
	}

	return sockfd;
}

int init_in_socket6(struct in6_addr multiaddr, short port)
{
	int sockfd = socket(AF_INET6, SOCK_DGRAM, 0);
	if (sockfd < 0)	{
		perror("socket()");
		exit(EXIT_FAILURE);
	}

	struct sockaddr_in6 addr6;
	addr6.sin6_family = AF_INET6;
	addr6.sin6_port = htons(port);
	addr6.sin6_addr = multiaddr;

	if(bind(sockfd, (struct sockaddr*)&addr6, sizeof(addr6)) < 0)
	{
		addr6.sin6_addr = in6addr_any;
		if(bind(sockfd, (struct sockaddr*)&addr6, sizeof(addr6)) < 0)
		{
			perror("bind()");
			exit(EXIT_FAILURE);
		}
	}
	return sockfd;
}

/** Initialize socket for sending multicast data */
int init_out_socket()
{
	int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
	if (sockfd < 0) {
		perror("socket()");
		exit(EXIT_FAILURE);
	}

	return sockfd;
}

int init_out_socket6()
{
	int sockfd = socket(AF_INET6, SOCK_DGRAM, 0);
	if (sockfd < 0) {
		perror("socket()");
		exit(EXIT_FAILURE);
	}

	return sockfd;
}

/** Close a socket */
void free_socket(int sockfd)
{
	close(sockfd);
}

/** Wait for data up to `duration' seconds */
int wait_for_data(int sockfd, int duration, int packet_limit)
{
	const char message[] = MESSAGE;
	char buffer[] = MESSAGE;
	memset(buffer, 0, sizeof(buffer));

	int num_received = 0;

	fd_set receive_fd_set;
	struct timeval timeout;

	time_t deadline = time(NULL) + duration;

	printv("Receiving\n");

	while (1) {
		int ret = 0;
		FD_ZERO(&receive_fd_set);
		FD_SET(sockfd, &receive_fd_set);

		if (duration == 0) {
			timeout.tv_sec  = 5;
			timeout.tv_usec = 0;
		} else {
			time_t now = time(NULL);
			if ((deadline - now) <= 0)
				break;

			timeout.tv_sec  = deadline - now;
			timeout.tv_usec = 0;
		}

		ret = select(sockfd + 1, &receive_fd_set, NULL, NULL, &timeout);
		if (ret == -1) {
			perror("select()");
			break;
		} else if (ret ) {
			recv(sockfd, buffer, sizeof(buffer), 0);
			if (strncmp(message, buffer, sizeof(buffer)) == 0) {
				num_received++;

				printv(".");
				if (!(num_received % 10))
					printv("\n");

				if (packet_limit > 0 && num_received > packet_limit)
					break;
			}
		} else {
			printf("No data within %lu seconds.\n", timeout.tv_sec);
			break;
		}
	}

	printv("\n");

	return num_received;
}

/** Send data for specified amount of time */
int send_data(int sockfd, struct in_addr multiaddr, short port,
					int pkts, double delay)
{
	const char message[] = MESSAGE;
	int i = 0;

	struct sockaddr_in addr;

	addr.sin_family = AF_INET;
	addr.sin_addr = multiaddr;
	addr.sin_port = htons(port);
	memset(&(addr.sin_zero), 0, sizeof(addr.sin_zero));

	struct timespec delay_value;
	delay_value.tv_sec = 0;
	delay_value.tv_nsec = delay * 999999999;

	printv("Sending...\n");

	while (i < pkts) {
		i++;
		sendto(sockfd, message, strlen(message), 0,
			(struct sockaddr*) &addr, sizeof(addr));

		printv(".");
		if (!(i % 10))
			printv("\n");

		nanosleep(&delay_value, NULL);
	}

	printv("\n");

	return i;
}

int send_data6(int sockfd, struct in6_addr multiaddr, short port,
		int pkts, double delay)
{
	const char message[] = MESSAGE;
	int i = 0;

	struct sockaddr_in6 addr6;

	addr6.sin6_family = AF_INET6;
	addr6.sin6_addr = multiaddr;
	addr6.sin6_port = htons(port);

	struct timespec delay_value;
	delay_value.tv_sec = 0;
	delay_value.tv_nsec = delay * 999999999;

	printv("Sending...\n");
	while (i < pkts) {
		i++;
		sendto(sockfd, message, strlen(message), 0,
			(struct sockaddr*) &addr6, sizeof(addr6));

		printv(".");
		if (!(i % 10))
			printv("\n");

		nanosleep(&delay_value, NULL);
	}
	printv("\n");

	return i;
}

int setup_sk4(struct parameters *params)
{
	int sockfd = init_out_socket(params);

	if (setsockopt(sockfd, IPPROTO_IP, IP_MULTICAST_LOOP,
			&(params->loop), sizeof(params->loop)) < 0) {
		perror("setsockopt");
		exit(EXIT_FAILURE);
	}

	if (setsockopt(sockfd, IPPROTO_IP, IP_MULTICAST_TTL,
			&(params->ttl), sizeof(params->ttl)) < 0) {
		perror("setsockopt");
		exit(EXIT_FAILURE);
	}
	if (setsockopt(sockfd, IPPROTO_IP, IP_MULTICAST_IF,
			&(params->interface), sizeof(params->interface)) < 0) {
		perror("setsockopt");
		exit(EXIT_FAILURE);
	}
	return sockfd;
}

int send_sk4(int sockfd, struct parameters *params)
{
	int num_sent = 0;
	num_sent = send_data(sockfd, params->multiaddr, params->port,
					params->pkts, params->delay);

	return num_sent;
}

int setup_sk6(struct parameters *params)
{
	int sockfd = init_out_socket6(params);

	if ( setsockopt(sockfd, IPPROTO_IPV6, IPV6_MULTICAST_LOOP,
				&(params->loop), sizeof(params->loop)) < 0 )
	{
		perror("setsockopt IPV6_MULTICAST_LOOP");
		exit(EXIT_FAILURE);
	}
	if ( setsockopt(sockfd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS,
				&(params->hops), sizeof(params->hops)) < 0 )
	{
		perror("setsockopt IPV6_MULTICAST_HOPS");
		exit(EXIT_FAILURE);
	}
	if ( setsockopt(sockfd, IPPROTO_IPV6, IPV6_MULTICAST_IF,
				&(params->if_index), sizeof(params->if_index)) < 0 )
	{
		perror("setsockopt IPV6_MULTICAST_IF");
		exit(EXIT_FAILURE);
	}

	return sockfd;
}

int send_sk6(int sockfd, struct parameters *params)
{
	int num_sent = 0;
	num_sent = send_data6(sockfd, params->multiaddr6, params->port,
					params->pkts, params->delay);

	return num_sent;
}

