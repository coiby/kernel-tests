# usex test suite
Usex (Unix System EXerciser) exercises and tests several kernel subsystems:
I/O, virtual memory, dhrystone benchmark, whetstone benchmark, transfer rate,
and binary tests.

## Contributions
Please make any test contributions needed directly to the upstream version of
the case at https://gitlab.com/jbastianrh/usex

## How to run it
Please refer to the top-level README.md for common dependencies.

### Install dependencies
```bash
root# bash ../../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```
