# module_diff test
# This is a test wrapper for kernel/module_diff

## How to run it
Please refer to the top-level README.md for common dependencies.

### Install dependencies
```bash
root# bash ../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```

### Module list
There are 4 architeches: x86_64, s390x, ppc64le and aarch64
and the variants based on these archs:
|
| -- x86_64 -- stock -- stock
|           |      | -- debug
|           | -- rt -- rt
|                 | -- debug
| -- aarch64 -- aarch64 -- aarch64
|            |        | -- deubg
|            | -- aarch64-rt -- aarch64-rt
|            |             | -- aarch64-rt-debug
|            | -- aarch64-64k -- aarch64-64k
|            |              | -- aarch64-64k-debug
|            | -- aarch64-rt-64k -- aarch64-rt-64k
|                              | -- aarch64-rt-64k-debug
| -- s390x -- s390x
|        | -- debug
| -- ppc64le -- ppc64le
           | -- debug

Such as on aarch64, we use aarch64 as the basic module list, and
put the increment to aarch64-rt or aarch64-64k list. Also the
debug variant incremment to debug list.
During test, we will put them all together.
e.g: baselist = aarch64 + aarch64-rt + aarch64-rt-debug

Then diff baselist with currentlist, and remove the modules in
'knownremoved' list, will get the missing module which is unexpected.

After comfirm the missing module has no harm, we can add it to
'knownremoved' list.
