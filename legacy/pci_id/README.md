# PCI ID Removal Check


## Test Description

Check that no PCI ID is removed.

### Dependencies

There are no outstanding dependencies beyond the tooling already
present in most RHEL systems. But to be pedantic:

## Dependencies

There are no outstanding dependencies beyond the tooling already
present in most RHEL systems. But to be pedantic:

| package       |  binaries                                                  |
|---------------|------------------------------------------------------------|
| kmod          | modinfo                                                    |
| grep          | grep                                                       |
| coreutils     | comm, mktemp, readlink, basename, dirname, sort, uniq, cat |
| rpm           | rpm, rpm2cpio                                              |
| sed           | sed                                                        |
| findutils     | find, xargs                                                |
| bash          | bash                                                       |
| cpio          | cpio                                                       |
| file          | file                                                       |
| gawk          | awk                                                        |
| binutils      | nm                                                         |
| restraint     | rstrnt-report-result and friends                           |

To fetch the baseline package versions, either yum or dnf is required.

As kernel modules may be compressed, the following are required as well,
although you'll probably go by with just the first one.

| package        | binaries |
|----------------|----------|
| xz             | xzcat    |
| gzip           | zcat     |
| bzip2          | bzcat    |
| xz-lzma-compat | lzcat    |
| lzop           | lzop     |
| lz4            | lz4      |
| zstd           | unzstd   |
| tar            | tar      |

### Install dependencies
```bash
root# bash ../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```
