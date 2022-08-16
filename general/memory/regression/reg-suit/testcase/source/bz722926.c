/*
 * Read/write blocks from specified block device.
 *
 * 	Usage : rwblock [options] <blk_dev> <start_sec> 
 *
 *	See below for the list of options
 *
 *	Here block are user defined as in dd (by default 512, as a linux
 *	sector). It does not necessarily corresponds to device block size.
 */

#define _GNU_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <string.h>
#include <ctype.h>

#include <sys/types.h>
#include <sys/stat.h>

#define SECTOR 512  // sector size
#define KILO  1024


/* print style */
#define PALL	 0 /* print all buffer */
#define PSECTOR	 1 /* print the begining of all sectors */
#define PBLOCK   2 /* print the begining of all blocks */
#define PCOMPACT 3 /* print repetitive char only once */
#define PTUNE	 4 /* print the begining of blocks of parametrable size */

int o_blksz = SECTOR, o_verb = 0, o_print_style = PALL, o_print_blksz = 0;

#define MAXCOUNT	KILO
#define MINBLKSZ	9  /* power of two (512) */
#define MAXBLKSZ	16 /* power of two (64k) */
#define RANDOM_BUF	1
#define RANDOM_START	2
#define RANDOM_CNT	4
#define RANDOM_BLKSZ	8
#define RANDOM_RW	16
#define RANDOM_ALL	0xFFFFFFFF

#define printverb(args...) \
	({ if (o_verb) printf(args); })

ssize_t rw_op(int fd, void *buf, size_t count, int write_option)
{
	if (write_option) {
		printverb("write(%i, 0x%p, %zu)\n", fd, buf, count);
		return write(fd, buf, count);
	} else {
		printverb("read(%i, 0x%p, %zu)\n", fd, buf, count);
		return read(fd, buf, count);
	}
}

void usage()
{
	fprintf(stderr, "Usage: rwblock [-b <blksz>] [-n <count>] [-l <repeat>]"
		" [-sw] <blk_dev> <start>\n");
	exit(EXIT_FAILURE);
}

void printbuf(char *buf, int bufsz, int loop, int blknum)
{
	char *s;
	int blksz = o_blksz;

	printf("(%i,%i):", loop, blknum);

	switch (o_print_style) {
	case PALL:
		buf[bufsz-1] = 0;
		printf("\t >%s<\n", buf);
		break;
	case PSECTOR:
	case PTUNE:
		blksz = o_print_blksz ? o_print_blksz : SECTOR;
	case PBLOCK:
		for (s = buf; s < buf+bufsz; s += blksz)
			printf("\t >%.8s...< (*%i)\n", s, blksz);
		break;
	case PCOMPACT:
		for (s = buf; s < buf+bufsz;) {
			int count = 0;
			char c = *s;
			while ((*s == c) && (s < buf+bufsz)) {
				count++;
				s++;
			}
			printf("\t '%.1s'  x%i", &c, count);
			if (!(count % SECTOR))
				printf(" (%i sectors)", count / SECTOR);
			if (!(count % KILO))
				printf(" (%i kB)", count / KILO);
			if (!(count % o_blksz))
				printf(" (%i blocks)", count / o_blksz);
			printf("\n");
		}
		break;
	}
}

void randomize() {
	unsigned int seed;
	FILE* urandom = fopen("/dev/urandom", "r");
	fread(&seed, sizeof(int), 1, urandom);
	fclose(urandom);
	srand(seed);
}

void randomly_fill(char *buf, int len)
{
	int i;

	for (i = 0; i < len; i++)
		buf[i] = rand();
}

int main(int argc, char *argv[])
{
	int fd, i, j, opt, bufsz;
	int o_nloop = 1, o_count = 1, o_serial = 0, o_write = 0, o_print = 0;
	int o_rand = 0, a_start = 0;
	char o_char = '*', a_fname[_POSIX_PATH_MAX];
	int openrw_option = O_RDONLY, nops_per_loop;
	unsigned long ret;
	void *buf;

	randomize();

	while ((opt = getopt(argc, argv, "b:c:l:n:p::r::svw")) != -1) {
		switch (opt) {
		case 'b': /* Block: set block size */
			o_blksz = atoi(optarg);
			break;
		case 'c': /* Char: set the character used to fill blocks */
			o_char = optarg[0];
			break;
		case 'l': /* Loop: repeat r/w operation several times */
			o_nloop = atoi(optarg);
			break;
		case 'n': /* set the number of block to read/write */
			o_count = atoi(optarg);
			break;
		case 'p': /*
			   * Print: display the content of read/written blocks
			   *
			   * By default print all buffer.
			   * 
			   * If suboption is:
			   * 's' (Sector): print the beginning of all sectors
			   * 'b' (Block): print the beginning of all blocks
			   * 'c' (Compact): print repetitive char only once
			   * x (a number): print the beginning of printing
			   *               blocks of size defined by x.
			   *               The size can be different than the
			   *               one defined by -b option.
			   */
			o_print = 1;
			if (optarg) {
				switch (optarg[0]) {
				case 's':
					o_print_style = PSECTOR;
					break;
				case 'b':
					o_print_style = PBLOCK;
					break;
				case 'c':
					o_print_style = PCOMPACT;
					break;
				default:
					if(isdigit(optarg[0])) {
						o_print_style = PTUNE;
						o_print_blksz = atoi(optarg);
					}
				}
			}
			break;
		case 'r': /*
			   * Random: use random parameters
			   *
			   * If no suboption is provided, write buffer is filled
			   * with random content.
			   */
			if (!optarg) {
				/* by default, we only use random buf */
				o_rand = RANDOM_BUF;
				break;
			}
			for (i = 0; optarg[i]; i++)
				switch (optarg[i]) {
				case 'c': /* Char: fill write buffer with
					   * random content */
					o_rand |= RANDOM_BUF;
					break;
				case 't': /* sTart: TODO: NOT IMPLEMENTED */
					o_rand |= RANDOM_START;
					break;				
				case 'n': /* couNt: random number of blocks */
					o_rand |= RANDOM_CNT;
					break;
				case 'b': /* Block size */
					o_rand |= RANDOM_BLKSZ;
					break;
				case 'w': /* Write: random rw status */ 
					o_rand |= RANDOM_RW;
					break;
				case 'a': /* All: all of the above */
					o_rand = RANDOM_ALL;
					break;
				}
			if (o_rand | RANDOM_CNT) {
				o_count = rand() % MAXCOUNT;
				printverb("random count: %i\n", o_count);
			}
			if (o_rand | RANDOM_BLKSZ) {
				o_blksz = 1 <<
					(rand() % (MAXBLKSZ - MINBLKSZ)
					 + MINBLKSZ);
				printverb("random blksz: %i\n", o_blksz);
			}
			if (o_rand |= RANDOM_RW) {
				o_write = rand() % 2;
				openrw_option = O_RDWR;
				if (o_write)
					printverb("random write\n");
				else
					printverb("random read\n");
			}
			break;
		case 's': /*
			   * Serial: read/write N times 1 block instead of
			   * 1 times N blocks
			   */
			o_serial = 1;
			break;
		case 'v': /* Verbose : be verbose */
			o_verb = 1;
			break;
		case 'w': /* Write: do write operations (read by default) */
			openrw_option = O_WRONLY;
			o_write = 1;
			break;
		default: /* '?' */
			fprintf(stderr, "Unknown option: -%c\n", opt);
			usage();
		}
	}

	if ( argc - optind < 1 ) {
		usage();
	}
	strncpy(a_fname, argv[optind], _POSIX_PATH_MAX);

	if ( argc - optind >= 2 )
		a_start = atoi(argv[optind+1]);

	nops_per_loop = o_serial ? o_count : 1;
	bufsz = o_serial ? o_blksz : o_count * o_blksz;
	printverb("ops/loop = %i, bufsz = %i\n", nops_per_loop, bufsz);
	ret = posix_memalign(&buf, o_blksz, bufsz);
	if (ret != 0) {
		printf("blksz = %i, bufsz = %i\n", o_blksz, bufsz);
		perror("posix_memalign");	
		exit(EXIT_FAILURE);
	}
	if (o_write) {
		if (o_rand & RANDOM_BUF)
			randomly_fill(buf, bufsz);
		else
			memset(buf, o_char, bufsz);
	}

	fd = open(a_fname, openrw_option|O_DIRECT);
	if (fd < 0) {
		perror("open");	
		exit(EXIT_FAILURE);
	}

	for (i = 0; i < o_nloop; i++) {
		printverb("lseek(%i, %i, %i)\n",
			  fd, a_start * o_blksz, SEEK_SET);
		ret = lseek(fd, a_start * o_blksz, SEEK_SET);	
		if (ret < 0) {
			perror("lseek");
			fprintf(stderr, "ret = %lu\n", ret);
			exit(EXIT_FAILURE);
		}

		for (j = 0; j < nops_per_loop; j++) {
			ret = rw_op(fd, buf, bufsz, o_write);
			if (ret != bufsz) {
				if (o_write)
					perror("write");
				else
					perror("read");
				exit(EXIT_FAILURE);
			}
			if(o_print)
				printbuf(buf, bufsz, i, j);
		}
	}
	free(buf);
	close(fd);

	return EXIT_SUCCESS;
}
