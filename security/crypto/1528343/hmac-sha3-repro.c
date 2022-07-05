#include <linux/if_alg.h>
#include <sys/socket.h>
#include <errno.h>
#include <stdio.h>

#define SOL_ALG		279

int main()
{
	int algfd, ret;
	struct sockaddr_alg addr = {
		.salg_type = "hash",
		.salg_name = "hmac(hmac(sha3-512-generic))",
	};
	char key[4096] = { 0 };
	
	algfd = socket(AF_ALG, SOCK_SEQPACKET, 0);
	if (algfd < 0) perror("socket(AF_ALG)");
	else printf("algfd=%d sz=%ld %ld %ld\n", algfd, sizeof(addr), sizeof(addr.salg_type), sizeof(addr.salg_name));

	ret = bind(algfd, (const struct sockaddr *)&addr, sizeof(addr));
	if (ret < 0) perror("bind()");
	else printf("bind()=%d\n", ret);

	ret = setsockopt(algfd, SOL_ALG, ALG_SET_KEY, key, sizeof(key));
	if (ret < 0) perror("setsockopt()");
	else printf("setsockopt()=%d\n", ret);
}
