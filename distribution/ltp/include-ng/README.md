
PURPOSE of /kernel/distribution/ltp/include-ng

### LTP Introduction
LTP is a famous test suite under Linux, We port LTP to Beaker
every 4 months (+/-1 month if needed). You can use this testcase
for RHEL/RHIVOS/Fedora testing.

### What's this
This is a include testcase, you should include it in your own ltp projects.

LTP test (e.g. generic, lite)
    \
     --> include-ng (include.sh), include (ltp-make.sh)
            \
             --> Kirk

### Requirements achieved in this library
 - Support use of both stable version (for RHEL) and upstream repo of LTP
 - Support customize TestFile for the different sub-component teams (mm, fs, timer, etc)
 - Filtering known issues in a unified way (e.g: RHEL9, fedora, upstream)
 - Patch backport and management work in a unified way (e.g: patches/20220527)
 - Each 'major release' have an LTP-version-specific version
 - Separate the requirement and data from test-wrapper code
 - Support to use the new LTP runner Kirk

### Install dependencies
```bash
root# bash ../../../cki_bin/pkgs_install.sh metadata
```
