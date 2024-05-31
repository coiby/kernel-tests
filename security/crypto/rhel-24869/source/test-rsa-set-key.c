#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>

#include <linux/crypto.h>
#include <linux/fips.h>
#include <crypto/akcipher.h>

// generate short 512-bits valid key, not valid in FIPS, e=65537
// openssl genrsa -f4 -verbose -out key.pem 512 # -f4 means: e is 65537 (0x010001)
// openssl rsa -in key.pem -outform DER -pubout -out pubkey.der
// openssl asn1parse -in pubkey.der -inform DER -offset 20 # kernel acceptable key starts from 20

unsigned char short_pubkey[] =
	"\x30\x48" // 2 bytes sequence header for content len 72
	"\x02\x41" // 2 bytes header for int len 65
	// 65 bytes pubkey
	"\x00\x9f\x6c\x83\x7a\x1c\x05\xfa\x3a\x85\xe3\x2b\x8a\xa2\xa3\xe8"
	"\xd7\x51\x78\xf9\xa6\x75\xdc\x79\x09\xf5\x75\x95\xf3\xf6\x40\x4c"
	"\x08\x1b\xac\xa7\xab\x72\xb5\x08\x88\x36\x5e\xf0\x39\x88\xc7\x39"
	"\x16\x1f\x34\x44\xfd\x85\x35\x6f\x10\x44\xfd\x3e\x8e\xca\x49\xdd\x09"
	"\x02\x03" // 2 bytes header for int len 3
	"\x01\x00\x01"; // 3 bytes e

// generate long 2048-bits valid key, valid in FIPS, e=65537
// openssl genrsa -f4 -verbose -out key.pem 2048 # -f4 means: e is 65537 (0x010001)
// openssl rsa -in key.pem -outform DER -pubout -out pubkey.der
// openssl asn1parse -in pubkey.der -inform DER -offset 24 # kernel acceptable key starts from 24

unsigned char long_pubkey[] =
	"\x30\x82\x01\x0a" // 4 bytes sequence header for content len 266
	"\x02\x82\x01\x01" // 4 bytes header for int len 257
	// 257 bytes pubkey
	"\x00\xaa\x13\x30\x07\x7c\xb3\x4a\xe4\x26\x56\x47\xc0\xf6\xa9\xc1"
	"\xd9\x5d\x53\xcb\x89\x02\xfa\xc9\x51\x4b\x55\xa7\x7a\x50\x21\x50"
	"\x53\x66\x9d\x0d\xe0\x9d\x3f\xb5\xff\xad\x0c\x99\xa0\x11\x0a\xe0"
	"\xb0\x76\x5b\xbf\xa8\x6c\x12\x1a\xb2\x36\x88\xbc\x21\xb7\xe0\xbc"
	"\x68\x20\x63\x87\xea\xa4\xc0\x4d\x69\x10\x90\x9c\x23\x76\x24\xb1"
	"\xd6\xd0\x7f\xe7\x2b\xa0\x7b\x3a\x8f\x43\xd5\x7e\x58\x77\xd6\x9e"
	"\x85\x9c\x6d\x47\xa9\xd7\xf2\x27\xc0\xa5\x54\x34\xbf\xea\xf9\xc9"
	"\x1a\x8d\x3c\xae\x9d\x09\x48\xf1\xd8\x7e\x23\x8f\xa0\xf1\x45\x80"
	"\x3d\x51\x6e\x31\xa5\x3d\xe2\xd9\xb3\xfb\x6f\x0a\x48\x48\x22\x42"
	"\xc7\x9a\xb3\x0a\x79\xd4\x50\x48\xf5\x28\xcc\xc3\xaa\x88\x06\xe0"
	"\xfc\xe7\x76\x7f\x57\x19\x26\x44\xdc\xee\x00\xc8\x7b\xac\x0f\x43"
	"\x7a\x1c\x40\xa7\xf0\x54\x2a\xd0\xea\x18\x4c\xb9\x2f\x78\x40\xfb"
	"\x39\x14\xb5\x06\xba\xd4\x63\x4c\xd7\x4d\x94\x52\x8a\x33\x80\x01"
	"\xf5\xfe\x69\xde\xad\x50\x63\x2d\x93\xb7\xdb\x30\xab\xca\x08\x60"
	"\x41\x2f\x34\xab\xde\xa4\x8d\x39\x63\xe4\x99\xd3\xa6\xd1\x7b\x24"
	"\xce\x88\x15\x10\xdd\x7d\x5b\xe4\x92\xa5\x58\x23\x3d\xe4\x8a\xdb\x99"
	"\x02\x03" // 2 bytes header for int len 3
	"\x01\x00\x01"; // 3 bytes e

static int __init rsa_set_key_test_init(void)
{
	struct crypto_akcipher *tfm = NULL;
	int err;
	int res;

	pr_info("RSA set-key test, FIPS = %d / %s\n", fips_enabled,
			fips_enabled ? "enabled" : "disabled");

	tfm = crypto_alloc_akcipher("rsa", 0, 0);
	if (IS_ERR(tfm)) {
		pr_info("could not allocate rsa akcipher handle\n");
		return -1; // PTR_ERR(skcipher);
	}

	// short 512-bits valid key
	pr_info(":: short 512-bits valid key\n");
	pr_info(":: should PASS on non-FIPS, FAIL on FIPS system\n");
	err = crypto_akcipher_set_pub_key(tfm, short_pubkey, sizeof(short_pubkey)-1);
	pr_info("result = %d / %s\n", err, err?"FAIL":"PASS");
	res = fips_enabled ? err : !err;

	// long 2048-bits valid key
	pr_info(":: long 2048-bits valid key, e=65537\n");
	pr_info(":: should PASS on FIPS and non-FIPS system\n");
	err = crypto_akcipher_set_pub_key(tfm, long_pubkey, sizeof(long_pubkey)-1);
	pr_info("result = %d / %s\n", err, err?"FAIL":"PASS");
	res = res && !err;

	// FIPS CONDITIONS:
	// (1) check if rsa public exponent is odd and
	// (2) check its value is between 2^16 < e < 2^256.

	// long key, even e > 2^16
	pr_info(":: long key, e is even, > 2^16, is 65538\n");
	pr_info(":: should PASS on non-FIPS and FAIL on FIPS system\n");
	long_pubkey[sizeof(long_pubkey)-2] = (char)2;
	err = crypto_akcipher_set_pub_key(tfm, long_pubkey, sizeof(long_pubkey)-1);
	pr_info("result = %d / %s\n", err, err?"FAIL":"PASS");
	res = res && (fips_enabled ? err : !err);

	// long key, odd e < 2^16
	pr_info(":: long key, e is odd, < 2^16, is 65535\n");
	pr_info(":: should PASS on non-FIPS and FAIL on FIPS system\n");
	long_pubkey[sizeof(long_pubkey)-2] = (char)0xff;
	long_pubkey[sizeof(long_pubkey)-3] = (char)0xff;
	long_pubkey[sizeof(long_pubkey)-4] = (char)0x00;
	err = crypto_akcipher_set_pub_key(tfm, long_pubkey, sizeof(long_pubkey)-1);
	pr_info("result = %d / %s\n", err, err?"FAIL":"PASS");
	res = res && (fips_enabled ? err : !err);

	// clean up
	crypto_free_akcipher(tfm);
	return res ? 0 : -EINVAL;
}

static void __exit rsa_set_key_test_exit(void)
{
	pr_info("RSA set-key test module exit\n");
}

module_init(rsa_set_key_test_init);
module_exit(rsa_set_key_test_exit);

MODULE_DESCRIPTION("Kernel RSA set-key test");
MODULE_AUTHOR("Vladis Dronov <vdronoff@gmail.com>");
MODULE_AUTHOR("Dennis Li <denli@redhat.com>");
MODULE_LICENSE("GPL v2");