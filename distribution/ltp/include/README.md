# LTP library
Ported LTP include library for Beaker.

Requirements achieved in this library:
 1. Support use of both stable version (for RHEL) and upstream repo of LTP
 2. Support customize TestFile for the different sub-component teams (mm, fs, timer, etc)
 3. Filtering known issues in a unified way (e.g: RHEL5/6/7/8/9, fedora, upstream)
 4. Patch backport and management work in a unified way (e.g: patches/20220527)
 5. Each 'major release' have an LTP-version-specific version
 6. Separate the requirement and data from test-wrapper code


## How to run it
Please refer to the top-level README.md for common dependencies. For a complete detail, see PURPOSE file. 

### Install dependencies
```bash
root# bash ../../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```
