#include <linux/module.h>
#include <linux/scatterlist.h>
#include <crypto/akcipher.h>
#include <linux/kernel.h>
#include <linux/crypto.h>
#include <linux/err.h>
#include <linux/gfp.h>


MODULE_LICENSE("GPL");
MODULE_AUTHOR("Dennis Li");
MODULE_DESCRIPTION("Test RSA decryption function is avaliable");


struct akcipher_testvec {
	const unsigned char *key;
	const unsigned char *m;
	const unsigned char *c;
	unsigned int key_len;
	unsigned int m_size;
	unsigned int c_size;
};

/*
 * RSA test vectors. Borrowed from openSSL.
 */

static const struct akcipher_testvec vecs = {
	.key =
	"\x30\x81\x9A" /* sequence of 154 bytes */
	"\x02\x01\x01" /* version - integer of 1 byte */
	"\x02\x41" /* modulus - integer of 65 bytes */
	"\x00\xAA\x36\xAB\xCE\x88\xAC\xFD\xFF\x55\x52\x3C\x7F\xC4\x52\x3F"
	"\x90\xEF\xA0\x0D\xF3\x77\x4A\x25\x9F\x2E\x62\xB4\xC5\xD9\x9C\xB5"
	"\xAD\xB3\x00\xA0\x28\x5E\x53\x01\x93\x0E\x0C\x70\xFB\x68\x76\x93"
	"\x9C\xE6\x16\xCE\x62\x4A\x11\xE0\x08\x6D\x34\x1E\xBC\xAC\xA0\xA1"
	"\xF5"
	"\x02\x01\x11" /* public key - integer of 1 byte */
	"\x02\x40" /* private key - integer of 64 bytes */
	"\x0A\x03\x37\x48\x62\x64\x87\x69\x5F\x5F\x30\xBC\x38\xB9\x8B\x44"
	"\xC2\xCD\x2D\xFF\x43\x40\x98\xCD\x20\xD8\xA1\x38\xD0\x90\xBF\x64"
	"\x79\x7C\x3F\xA7\xA2\xCD\xCB\x3C\xD1\xE0\xBD\xBA\x26\x54\xB4\xF9"
	"\xDF\x8E\x8A\xE5\x9D\x73\x3D\x9F\x33\xB3\x01\x62\x4A\xFD\x1D\x51"
	"\x02\x01\x00" /* prime1 - integer of 1 byte */
	"\x02\x01\x00" /* prime2 - integer of 1 byte */
	"\x02\x01\x00" /* exponent1 - integer of 1 byte */
	"\x02\x01\x00" /* exponent2 - integer of 1 byte */
	"\x02\x01\x00", /* coefficient - integer of 1 byte */
	.m = "\x54\x85\x9b\x34\x2c\x49\xea\x2a",
	.c =
	"\x63\x1c\xcd\x7b\xe1\x7e\xe4\xde\xc9\xa8\x89\xa1\x74\xcb\x3c\x63"
	"\x7d\x24\xec\x83\xc3\x15\xe4\x7f\x73\x05\x34\xd1\xec\x22\xbb\x8a"
	"\x5e\x32\x39\x6d\xc1\x1d\x7d\x50\x3b\x9f\x7a\xad\xf0\x2e\x25\x53"
	"\x9f\x6e\xbd\x4c\x55\x84\x0c\x9b\xcf\x1a\x4b\x51\x1e\x9e\x0c\x06",
	.key_len = 157,
	.m_size = 8,
	.c_size = 64,
};


static int __init test_rsa_decryption_init(void)
{
	struct crypto_akcipher *tfm;
	struct akcipher_request *req;

	char *xbuf;
	void *outbuf_dec = NULL;
	unsigned int out_len_max;
	int ret = -ENOMEM;
	struct scatterlist src, dst;


	xbuf = (void *)__get_free_page(GFP_KERNEL);
	if (!xbuf) {
		printk(KERN_ERR "Failed to allocate memory for buffer\n");
		return -ENOMEM;
	}

	tfm = crypto_alloc_akcipher("rsa", 0, 0);

	req = akcipher_request_alloc(tfm, GFP_KERNEL);
	if (!req) {
		ret = -ENOMEM;
		goto free_tfm;
	}

	ret = crypto_akcipher_set_priv_key(tfm, vecs.key, vecs.key_len);
	if (ret)
		goto free_req;


	out_len_max = crypto_akcipher_maxsize(tfm);
	outbuf_dec = kzalloc(out_len_max, GFP_KERNEL);


	memcpy(xbuf, vecs.c, vecs.c_size);
	sg_init_one(&src, xbuf, vecs.c_size);
	sg_init_one(&dst, outbuf_dec, out_len_max);
	akcipher_request_set_crypt(req, &src, &dst, vecs.c_size, out_len_max);

	ret = crypto_akcipher_decrypt(req);
	if (ret) {
		printk(KERN_ERR "RSA decryption failed %d\n", ret);
		goto free_req;
	}

	printk(KERN_INFO "RSA decryption successful\n");

free_req:
	akcipher_request_free(req);
free_tfm:
	crypto_free_akcipher(tfm);
	return ret;
}

static void __exit test_rsa_decryption_exit(void)
{
	printk(KERN_INFO "Exiting RSA decryption module\n");
}

module_init(test_rsa_decryption_init);
module_exit(test_rsa_decryption_exit);