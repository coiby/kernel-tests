# erofs-utils tests
EROFS (Enhanced Read-Only File System) filesystem tests.  Thew aim is to
form a generic read-only filesystem solution for various read-only use
cases instead of just focusing on storage space saving without
considering any side effects of runtime performance.

This is a Red Hat wrapper of the [public suite](https://github.com/erofs/erofs-utils/tree/experimental-tests/tests/erofs)

### Install dependencies
```bash
root# bash ../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```
